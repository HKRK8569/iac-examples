import { EC2Client } from "@aws-sdk/client-ec2";
import { SchedulerClient } from "@aws-sdk/client-scheduler";
import { processEvent } from "./auto-stop.mjs";

export function createHandler(dependencies) {
  return async (event, context) => {
    const required = (name) => {
      const value = dependencies.env[name];
      if (!value) throw new Error(`Missing environment variable: ${name}`);
      return value;
    };
    const afterMinutes = Number(required("AUTO_STOP_AFTER_MINUTES"));
    if (!Number.isInteger(afterMinutes) || afterMinutes < 1 || afterMinutes > 1440) {
      throw new Error("AUTO_STOP_AFTER_MINUTES must be an integer from 1 to 1440");
    }
    const result = await processEvent(event, {
      instanceId: required("INSTANCE_ID"),
      afterMinutes,
      scheduleGroup: required("SCHEDULE_GROUP"),
      schedulerRoleArn: required("SCHEDULER_ROLE_ARN"),
      functionArn: context.invokedFunctionArn.split(":").slice(0, 7).join(":"),
    }, dependencies.ec2, dependencies.scheduler, dependencies.now());
    dependencies.log(JSON.stringify(result));
    return result;
  };
}

export const handler = createHandler({
  ec2: new EC2Client({}),
  scheduler: new SchedulerClient({}),
  env: process.env,
  now: () => new Date(),
  log: console.log,
});
