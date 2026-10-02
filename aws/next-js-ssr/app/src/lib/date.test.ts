import { describe, expect, it } from "vitest";
import { formatReportDate } from "./date";

describe("formatReportDate", () => {
  it("日本時間の年月日にフォーマットされる", () => {
    expect(formatReportDate(new Date("2026-07-30T00:00:00+09:00"))).toBe(
      "2026/07/30",
    );
  });

  it("UTCの日付は日本時間に変換される", () => {
    // UTC 23:00 は日本時間では翌日
    expect(formatReportDate(new Date("2026-07-30T23:00:00Z"))).toBe(
      "2026/07/31",
    );
  });
});
