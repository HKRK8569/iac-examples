import { count, desc, eq } from "drizzle-orm";
import { dbReader, dbWriter } from "@/db";
import { reports, type NewReport, type Report } from "@/db/schema";

export const REPORTS_PER_PAGE = 20;

export type ReportListMeta = {
  page: number;
  perPage: number;
  totalCount: number;
  totalPages: number;
  hasNext: boolean;
  hasPrev: boolean;
};

export type ReportListResult = {
  reports: Report[];
  meta: ReportListMeta;
};

// 一覧取得（新しい順・ページネーション付き）。読み取りなのでreaderを使う
export async function listReports(page = 1): Promise<ReportListResult> {
  // 不正なページ指定（0以下・小数・NaN）は1ページ目に丸める
  const currentPage = Number.isFinite(page) ? Math.max(1, Math.floor(page)) : 1;

  const [rows, [{ totalCount }]] = await Promise.all([
    dbReader
      .select()
      .from(reports)
      .orderBy(desc(reports.reportedAt), desc(reports.id))
      .limit(REPORTS_PER_PAGE)
      .offset((currentPage - 1) * REPORTS_PER_PAGE),
    dbReader.select({ totalCount: count() }).from(reports),
  ]);

  const totalPages = Math.max(1, Math.ceil(totalCount / REPORTS_PER_PAGE));

  return {
    reports: rows,
    meta: {
      page: currentPage,
      perPage: REPORTS_PER_PAGE,
      totalCount,
      totalPages,
      hasNext: currentPage < totalPages,
      hasPrev: currentPage > 1,
    },
  };
}

// 1件取得。見つからない場合はundefined
export async function getReport(id: number): Promise<Report | undefined> {
  const rows = await dbReader
    .select()
    .from(reports)
    .where(eq(reports.id, id))
    .limit(1);
  return rows[0];
}

// 日報の作成。書き込みなのでwriterを使う
export async function createReport(input: NewReport): Promise<Report> {
  const rows = await dbWriter.insert(reports).values(input).returning();
  return rows[0];
}
