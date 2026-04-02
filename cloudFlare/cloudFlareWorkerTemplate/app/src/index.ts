export default {
  async fetch(
    _req: Request,
    _env: unknown,
    _ctx: ExecutionContext,
  ): Promise<Response> {
    console.log("[http] request received");
    return new Response("Hello World!", {
      status: 200,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  },

  async scheduled(
    _controller: ScheduledController,
    _env: unknown,
    _ctx: ExecutionContext,
  ) {
    console.log("[scheduled] cron processed");
  },
};
