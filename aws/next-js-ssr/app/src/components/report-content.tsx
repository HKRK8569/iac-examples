import { formatReportDate } from "@/lib/date";

type Props = {
  title: string;
  body: string;
  reportedAt: Date;
  imageSrc: string | null;
};

// 記事と投稿前プレビューで同じレイアウトを使う。
export function ReportContent({ title, body, reportedAt, imageSrc }: Props) {
  return (
    <article>
      <time dateTime={reportedAt.toISOString()} className="block text-sm text-zinc-500">
        {formatReportDate(reportedAt)}
      </time>
      <h1 className="mt-1 break-words text-3xl font-bold">{title}</h1>

      {imageSrc && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={imageSrc} alt="" className="mt-6 w-full rounded-lg object-cover" />
      )}

      <div className="mt-6 whitespace-pre-wrap break-words leading-relaxed">{body}</div>
    </article>
  );
}
