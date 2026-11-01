// ALB用。DB障害をECSタスクの入れ替え条件にしない。
export const dynamic = "force-dynamic";

export async function GET() {
  return Response.json({ status: "ok" }, {
    headers: { "Cache-Control": "no-store" },
  });
}
