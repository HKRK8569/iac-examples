import type { ReportListMeta } from "@/db/queries/reports";

// APIのJSONレスポンス上の日報（Date型はJSON化で文字列になる）
export type ReportDto = {
  id: number;
  title: string;
  body: string;
  imageKey: string | null;
  reportedAt: string;
  createdAt: string;
};

export type ReportListResponse = {
  reports: ReportDto[];
  meta: ReportListMeta;
};
