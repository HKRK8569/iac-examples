import { describe, expect, it } from "vitest";
import {
  DescribeInstancesCommand, StopInstancesCommand,
} from "@aws-sdk/client-ec2";
import {
  CreateScheduleCommand, GetScheduleCommand, UpdateScheduleCommand,
} from "@aws-sdk/client-scheduler";
import { processEvent } from "../src/auto-stop.mjs";
import { createHandler } from "../src/index.mjs";

const awsError = (name) => Object.assign(new Error(name), { name });
const launch = new Date("2026-01-01T00:00:30Z");
const minutesLater = (minutes) => new Date(launch.getTime() + minutes * 60_000);

class FakeEc2 {
  instance = {
    InstanceId: "i-0123456789abcdef0", State: { Name: "running" }, LaunchTime: launch,
  };
  error;
  calls = [];
  async send(command) {
    this.calls.push(command);
    if (this.error) throw this.error;
    return command instanceof DescribeInstancesCommand
      ? { $metadata: {}, Reservations: [{ Instances: this.instance ? [this.instance] : [] }] }
      : { $metadata: {} };
  }
  get stops() { return this.calls.filter((command) => command instanceof StopInstancesCommand); }
}

class FakeScheduler {
  existing;
  getError;
  createError;
  calls = [];
  async send(command) {
    this.calls.push(command);
    if (command instanceof GetScheduleCommand) {
      if (this.getError) throw this.getError;
      if (!this.existing) throw awsError("ResourceNotFoundException");
      return this.existing;
    }
    if (command instanceof CreateScheduleCommand && this.createError) throw this.createError;
    this.existing = { ...command.input, $metadata: {} };
    return { $metadata: {} };
  }
  get creates() { return this.calls.filter((command) => command instanceof CreateScheduleCommand); }
  get updates() { return this.calls.filter((command) => command instanceof UpdateScheduleCommand); }
}

function fixture() {
  const settings = {
    instanceId: "i-0123456789abcdef0", afterMinutes: 60, scheduleGroup: "test-group",
    schedulerRoleArn: "arn:aws:iam::123456789012:role/scheduler",
    functionArn: "arn:aws:lambda:ap-northeast-1:123456789012:function:auto-stop",
  };
  const ec2 = new FakeEc2();
  const scheduler = new FakeScheduler();
  return {
    settings, ec2, scheduler,
    run: (event = { action: "reconcile" }, now = minutesLater(1)) =>
      processEvent(event, settings, ec2, scheduler, now),
  };
}
const stopEvent = () => ({ action: "stop", launch_time: launch.toISOString() });

describe("踏み台の自動停止", () => {
  it("現在の起動時刻を基準にUTCの単発停止予約を作成する", async () => {
    const f = fixture();
    expect((await f.run()).status).toBe("scheduled");
    const input = f.scheduler.creates[0].input;
    expect(input.ScheduleExpression).toBe("at(2026-01-01T01:01:00)");
    expect(input.ScheduleExpressionTimezone).toBe("UTC");
    expect(input.FlexibleTimeWindow).toEqual({ Mode: "OFF" });
    expect(input.ActionAfterCompletion).toBe("DELETE");
    expect(JSON.parse(input.Target.Input)).toEqual(stopEvent());
    expect(input.Target.Arn).toBe(f.settings.functionArn);
    expect(input.Target.RoleArn).toBe(f.settings.schedulerRoleArn);
    expect(f.ec2.stops).toHaveLength(0);
  });

  it("重複イベントを受信しても期限を延長せず同じ予約を更新しない", async () => {
    const f = fixture();
    await f.run();
    await f.run({ action: "reconcile" }, minutesLater(10));
    expect(f.scheduler.creates).toHaveLength(1);
    expect(f.scheduler.updates).toHaveLength(0);
  });

  it("停止までの時間を変更すると起動時刻を基準に予約を更新する", async () => {
    const f = fixture();
    await f.run();
    f.settings.afterMinutes = 120;
    await f.run();
    expect(f.scheduler.updates[0].input.ScheduleExpression).toBe("at(2026-01-01T02:01:00)");
    expect(f.ec2.stops).toHaveLength(0);
  });

  it("定期確認で制限時間を超えて起動中のインスタンスを停止する", async () => {
    const f = fixture();
    expect((await f.run({ action: "reconcile" }, minutesLater(61))).status).toBe("stop_requested");
    expect(f.ec2.stops[0].input).toEqual({ InstanceIds: [f.settings.instanceId] });
    expect(f.scheduler.creates).toHaveLength(0);
  });

  it("期限に達した予約の起動時刻が一致すれば停止する", async () => {
    const f = fixture();
    await f.run(stopEvent(), minutesLater(60));
    expect(f.ec2.stops).toHaveLength(1);
  });

  it("期限より早く呼び出された場合は停止せず予約し直す", async () => {
    const f = fixture();
    await f.run(stopEvent());
    expect(f.ec2.stops).toHaveLength(0);
    expect(f.scheduler.creates).toHaveLength(1);
  });

  it("古い起動に対する予約では起動し直したインスタンスを停止しない", async () => {
    const f = fixture();
    f.ec2.instance.LaunchTime = minutesLater(50);
    expect((await f.run(stopEvent(), minutesLater(61))).status).toBe("stale_schedule");
    expect(f.ec2.stops).toHaveLength(0);
    expect(f.scheduler.creates).toHaveLength(0);
  });

  it("起動するたびに異なる名前の停止予約を作成する", async () => {
    const f = fixture();
    await f.run();
    f.ec2.instance.LaunchTime = minutesLater(50);
    f.scheduler.existing = undefined;
    await f.run({ action: "reconcile" }, minutesLater(51));
    expect(f.scheduler.creates[0].input.Name).not.toBe(f.scheduler.creates[1].input.Name);
  });

  it("起動中でなければ停止処理も予約作成も行わない", async () => {
    const f = fixture();
    for (const state of ["pending", "stopped", "stopping", "shutting-down", "terminated"]) {
      f.ec2.instance.State = { Name: state };
      expect((await f.run()).status).toBe("not_running");
    }
    expect(f.ec2.stops).toHaveLength(0);
    expect(f.scheduler.creates).toHaveLength(0);
  });

  it("EC2の検索結果に対象インスタンスがなければ何もしない", async () => {
    const f = fixture();
    f.ec2.instance = undefined;
    expect((await f.run()).status).toBe("not_found");
    expect(f.ec2.stops).toHaveLength(0);
  });

  it("削除済みのインスタンスに対するエラーは無視する", async () => {
    const f = fixture();
    f.ec2.error = awsError("InvalidInstanceID.NotFound");
    expect((await f.run()).status).toBe("not_found");
  });

  it("EC2の権限エラーは呼び出し元へ返す", async () => {
    const f = fixture();
    f.ec2.error = awsError("UnauthorizedOperation");
    await expect(f.run()).rejects.toMatchObject({ name: "UnauthorizedOperation" });
  });

  it("Schedulerの権限エラーは呼び出し元へ返す", async () => {
    const f = fixture();
    f.scheduler.getError = awsError("AccessDeniedException");
    await expect(f.run()).rejects.toMatchObject({ name: "AccessDeniedException" });
    expect(f.scheduler.creates).toHaveLength(0);
  });

  it("予約作成が競合した場合は既存の予約を更新する", async () => {
    const f = fixture();
    f.scheduler.createError = awsError("ConflictException");
    await f.run();
    expect(f.scheduler.creates[0].input).toEqual(f.scheduler.updates[0].input);
  });

  it("予約作成の失敗は呼び出し元へ返す", async () => {
    const f = fixture();
    f.scheduler.createError = awsError("AccessDeniedException");
    await expect(f.run()).rejects.toMatchObject({ name: "AccessDeniedException" });
    expect(f.scheduler.updates).toHaveLength(0);
  });

  it("未対応または不正なイベントではAWS APIを呼び出さない", async () => {
    const f = fixture();
    for (const event of [{ action: "terminate" }, {}, null, "stop"]) {
      expect((await f.run(event)).status).toBe("ignored");
    }
    expect(f.ec2.calls).toHaveLength(0);
  });

  it("イベントに別のインスタンスIDがあっても設定済みの踏み台だけを停止する", async () => {
    const f = fixture();
    await f.run({ ...stopEvent(), instance_id: "i-another-instance" }, minutesLater(60));
    expect(f.ec2.stops[0].input.InstanceIds).toEqual([f.settings.instanceId]);
  });

  it("Lambdaの入口で環境変数を読み込みARNからバージョン指定を除く", async () => {
    const f = fixture();
    const logs = [];
    const handler = createHandler({
      ec2: f.ec2, scheduler: f.scheduler, now: () => minutesLater(1), log: (line) => logs.push(line),
      env: {
        INSTANCE_ID: f.settings.instanceId, AUTO_STOP_AFTER_MINUTES: "60",
        SCHEDULE_GROUP: f.settings.scheduleGroup, SCHEDULER_ROLE_ARN: f.settings.schedulerRoleArn,
      },
    });
    await handler({ action: "reconcile" }, { invokedFunctionArn: `${f.settings.functionArn}:version` });
    expect(f.scheduler.creates[0].input.Target.Arn).toBe(f.settings.functionArn);
    expect(JSON.parse(logs[0]).status).toBe("scheduled");
  });

  it("旧形式の時刻を持つ予約でも起動時刻を照合できる", async () => {
    const f = fixture();
    await f.run({ action: "stop", launch_time: "2026-01-01T00:00:30+00:00" }, minutesLater(60));
    expect(f.ec2.stops).toHaveLength(1);
  });

  it("予約に起動時刻が含まれていなければ停止しない", async () => {
    const f = fixture();
    expect((await f.run({ action: "stop" }, minutesLater(61))).status).toBe("stale_schedule");
    expect(f.ec2.stops).toHaveLength(0);
  });

  it("停止までの時間が不正ならAWS APIを呼び出す前にエラーにする", async () => {
    const f = fixture();
    const handler = createHandler({
      ec2: f.ec2, scheduler: f.scheduler, now: () => minutesLater(1), log: () => {},
      env: { AUTO_STOP_AFTER_MINUTES: "0" },
    });
    await expect(handler({ action: "reconcile" }, { invokedFunctionArn: f.settings.functionArn })).rejects.toThrow(/1 to 1440/);
    expect(f.ec2.calls).toHaveLength(0);
  });
});
