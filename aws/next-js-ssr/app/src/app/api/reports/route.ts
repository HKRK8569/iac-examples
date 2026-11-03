import { NextRequest, NextResponse } from "next/server";
import { createReport, listReports } from "@/db/queries/reports";

// 一覧取得（CSRの一覧ページから呼ばれる。CloudFrontの/api/*はキャッシュされない）
export async function GET(req: NextRequest) {
  const page = Number(req.nextUrl.searchParams.get("page") ?? "1");
  const result = await listReports(page);
  return NextResponse.json(result);
}

// 日報の投稿
export async function POST(req: NextRequest) {
  const json = await req.json().catch(() => null);
  if (json === null) {
    return NextResponse.json({ message: "invalid json" }, { status: 400 });
  }

  const { title, body, reportedAt, imageKey } = json as Record<string, unknown>;

  if (typeof title !== "string" || !title.trim() || title.length > 200) {
    return NextResponse.json(
      { message: "タイトルは1〜200文字で入力してください" },
      { status: 400 },
    );
  }
  if (typeof body !== "string" || !body.trim()) {
    return NextResponse.json(
      { message: "本文を入力してください" },
      { status: 400 },
    );
  }
  if (typeof reportedAt !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(reportedAt)) {
    return NextResponse.json(
      { message: "日付はYYYY-MM-DD形式で指定してください" },
      { status: 400 },
    );
  }
  // imageKeyは任意。指定される場合はupload-urlが発行したキー形式のみ許可
  if (
    imageKey !== undefined &&
    imageKey !== null &&
    (typeof imageKey !== "string" || !imageKey.startsWith("images/"))
  ) {
    return NextResponse.json(
      { message: "imageKeyが不正です" },
      { status: 400 },
    );
  }

  const report = await createReport({
    title: title.trim(),
    body,
    imageKey: (imageKey as string | undefined) ?? null,
    // 対象日はJSTの0時として保存する
    reportedAt: new Date(`${reportedAt}T00:00:00+09:00`),
  });

  return NextResponse.json(report, { status: 201 });
}
