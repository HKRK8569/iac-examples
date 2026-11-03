import { checkDatabaseReadiness } from "../../../db/readiness";

// デプロイ確認・監視用。毎回writer / readerでDBの読み取りを確認する。
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    await checkDatabaseReadiness();
    return Response.json({ status: "ready" }, {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    console.error("Database readiness check failed", error);
    return Response.json({ status: "not_ready" }, {
      status: 503,
      headers: { "Cache-Control": "no-store" },
    });
  }
}
