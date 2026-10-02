// 日報の日付表示用フォーマット（例: 2026/07/30）
export function formatReportDate(date: Date): string {
  return new Intl.DateTimeFormat("ja-JP", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    timeZone: "Asia/Tokyo",
  }).format(date);
}
