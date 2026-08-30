import Link from "next/link";
import { notFound } from "next/navigation";
import { getReport } from "@/db/queries/reports";
import { formatReportDate } from "@/lib/date";
import { imageUrl } from "@/lib/image";

// 記事ページ（毎回SSR・キャッシュなし）
// 将来の記事編集機能で変更を即時反映させたいため、エッジキャッシュはしない方針。
// Next.jsが返すデフォルトの Cache-Control: no-store をCloudFrontが尊重するので、
// インフラ側（ssr_cacheポリシー）の変更は不要。
// エッジで60秒キャッシュしたくなった場合は以下の2つを追加する:
//   export const revalidate = 60;
//   export function generateStaticParams() { return []; } // これがないと完全動的扱いでs-maxageが付かない

export default async function ReportPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const numericId = Number(id);
  if (!Number.isInteger(numericId) || numericId < 1) {
    notFound();
  }

  const report = await getReport(numericId);
  if (!report) {
    notFound();
  }

  const src = imageUrl(report.imageKey);

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <Link href="/" className="text-sm text-zinc-500 hover:underline">
        ← 一覧に戻る
      </Link>

      <article className="mt-6">
        <time className="block text-sm text-zinc-500">
          {formatReportDate(report.reportedAt)}
        </time>
        <h1 className="mt-1 text-3xl font-bold">{report.title}</h1>

        {src && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={src}
            alt=""
            className="mt-6 w-full rounded-lg object-cover"
          />
        )}

        <div className="mt-6 whitespace-pre-wrap leading-relaxed">
          {report.body}
        </div>
      </article>
    </div>
  );
}
