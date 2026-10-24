import Link from "next/link";
import { ReportForm } from "@/components/report-form";

// アップロードページ（CSR）
// 画像は署名付きURL経由でブラウザからS3へ直接アップロードする
export default function NewReportPage() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <Link href="/" className="text-sm text-zinc-500 hover:underline">
        ← 一覧に戻る
      </Link>
      <h1 className="mt-6 mb-8 text-2xl font-bold">日報を書く</h1>
      <ReportForm />
    </div>
  );
}
