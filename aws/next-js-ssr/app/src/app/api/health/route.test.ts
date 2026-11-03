import { afterEach, expect, it, vi } from "vitest";
import { GET } from "./route";

afterEach(() => vi.unstubAllEnvs());

it("DB設定が不正でもアプリの応答を200で返し、結果をキャッシュしない", async () => {
  vi.stubEnv("DB_SSL_MODE", "invalid");
  vi.stubEnv("DB_WRITER_ENDPOINT", "unreachable.example");

  const response = await GET();

  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ status: "ok" });
  expect(response.headers.get("Cache-Control")).toBe("no-store");
});
