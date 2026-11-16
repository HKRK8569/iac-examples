interface Env {
  STATE_KV: KVNamespace;
}

async function incrementCount(env: Env): Promise<number> {
  // KVの更新はアトミックではないため、同時実行時は加算を取りこぼす場合がある。
  const current = await env.STATE_KV.get("invocation_count");
  const count = Number(current ?? "0") + 1;
  await env.STATE_KV.put("invocation_count", String(count));
  return count;
}

export default {
  async fetch(
    _req: Request,
    env: Env,
    _ctx: ExecutionContext,
  ): Promise<Response> {
    const count = await incrementCount(env);
    console.log(`[http] invocation_count=${count}`);
    return new Response(`Hello World! invocation_count=${count}`, {
      status: 200,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  },

  async scheduled(
    _controller: ScheduledController,
    env: Env,
    _ctx: ExecutionContext,
  ) {
    const count = await incrementCount(env);
    console.log(`[scheduled] invocation_count=${count}`);
  },
};
