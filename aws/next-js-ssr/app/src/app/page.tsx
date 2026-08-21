import Link from "next/link";
import { ReportList } from "@/components/report-list";

// 一覧ページ（CSR）
// シェルのHTMLは静的（CloudFrontから配信）で、データはクライアントが /api/reports から取得する。
// /api/* はCloudFrontでキャッシュしないため、投稿が即時反映される
export default function Home() {
  return (
    <div className="mx-auto max-w-5xl px-4 py-10">
      <header className="mb-8 flex items-center justify-between">
        <h1 className="text-2xl font-bold">日報</h1>
        <Link
          href="/reports/new"
          className="rounded bg-zinc-900 px-4 py-2 text-sm text-white transition hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900"
        >
          日報を書く
        </Link>
      </header>
      <ReportList />
    </div>
  );
}
