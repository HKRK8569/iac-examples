import {
  DescribeInstancesCommand,
  StopInstancesCommand,
} from "@aws-sdk/client-ec2";
import {
  CreateScheduleCommand,
  GetScheduleCommand,
  UpdateScheduleCommand,
} from "@aws-sdk/client-scheduler";

const record = (value) =>
  typeof value === "object" && value !== null;

function errorCode(error) {
  return record(error) && typeof error.name === "string" ? error.name : undefined;
}

// Compare only explicitly configured fields; SDK responses include extra metadata.
function contains(actual, expected) {
  if (record(expected)) {
    return record(actual) && Object.entries(expected).every(([key, value]) => contains(actual[key], value));
  }
  return actual === expected;
}

export async function processEvent(
  event,
  settings,
  ec2,
  scheduler,
  now,
) {
  if (!record(event) || (event.action !== "reconcile" && event.action !== "stop")) {
    return { status: "ignored" };
  }

  let response;
  try {
    response = await ec2.send(new DescribeInstancesCommand({ InstanceIds: [settings.instanceId] }));
  } catch (error) {
    if (errorCode(error) === "InvalidInstanceID.NotFound") return { status: "not_found" };
    throw error;
  }
  const instance = response.Reservations?.flatMap((reservation) => reservation.Instances ?? [])
    .find((item) => item.InstanceId === settings.instanceId);
  if (!instance) return { status: "not_found" };
  if (instance.State?.Name !== "running") return { status: "not_running" };
  const launch = instance.LaunchTime;
  if (!launch || !Number.isFinite(launch.getTime())) throw new Error("Running instance has no valid LaunchTime");

  // 既存の予約で使われているUTCオフセット形式の時刻も受け付ける。
  const expectedLaunch = typeof event.launch_time === "string" ? Date.parse(event.launch_time) : NaN;
  if (event.action === "stop" && expectedLaunch !== launch.getTime()) {
    return { status: "stale_schedule" };
  }
  const deadline = launch.getTime() + settings.afterMinutes * 60_000;
  if (now.getTime() >= deadline) {
    await ec2.send(new StopInstancesCommand({ InstanceIds: [settings.instanceId] }));
    return { status: "stop_requested", instance_id: settings.instanceId };
  }

  const scheduledAt = new Date(Math.ceil(deadline / 60_000) * 60_000);
  const parameters = {
    Name: `stop-${settings.instanceId}-${Math.floor(launch.getTime() / 1000)}`,
    GroupName: settings.scheduleGroup,
    ScheduleExpression: `at(${scheduledAt.toISOString().slice(0, 19)})`,
    ScheduleExpressionTimezone: "UTC",
    FlexibleTimeWindow: { Mode: "OFF" },
    ActionAfterCompletion: "DELETE",
    State: "ENABLED",
    Target: {
      Arn: settings.functionArn,
      RoleArn: settings.schedulerRoleArn,
      Input: JSON.stringify({ action: "stop", launch_time: launch.toISOString() }),
      RetryPolicy: { MaximumEventAgeInSeconds: 300, MaximumRetryAttempts: 2 },
    },
  };

  let existing;
  try {
    existing = await scheduler.send(new GetScheduleCommand({ Name: parameters.Name, GroupName: parameters.GroupName }));
  } catch (error) {
    if (errorCode(error) !== "ResourceNotFoundException") throw error;
    try {
      await scheduler.send(new CreateScheduleCommand(parameters));
    } catch (conflict) {
      if (errorCode(conflict) !== "ConflictException") throw conflict;
      await scheduler.send(new UpdateScheduleCommand(parameters));
    }
    return { status: "scheduled", schedule: parameters.Name };
  }
  if (!contains(existing, parameters)) await scheduler.send(new UpdateScheduleCommand(parameters));
  return { status: "scheduled", schedule: parameters.Name };
}
