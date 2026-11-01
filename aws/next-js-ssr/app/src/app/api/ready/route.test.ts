import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { Client } = vi.hoisted(() => ({ Client: vi.fn() }));
vi.mock("pg", () => ({ Client }));
vi.mock("server-only", () => ({}));

import { GET } from "./route";

function createClient() {
  return {
    on: vi.fn(),
    connect: vi.fn().mockResolvedValue(undefined),
    query: vi.fn().mockResolvedValue({ rows: [] }),
    end: vi.fn().mockResolvedValue(undefined),
  };
}

let writer: ReturnType<typeof createClient>;
let reader: ReturnType<typeof createClient>;

beforeEach(() => {
  writer = createClient();
  reader = createClient();
  Client.mockReset();
  Client.mockImplementationOnce(function () { return writer; });
  Client.mockImplementationOnce(function () { return reader; });
  vi.stubEnv("DB_WRITER_ENDPOINT", "writer.example");
  vi.stubEnv("DB_READER_ENDPOINT", "reader.example");
  vi.stubEnv("DB_SSL_MODE", "disable");
  vi.spyOn(console, "error").mockImplementation(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
});

describe("DBのreadiness確認", () => {
  it("writer / readerの読み取りが成功すれば、空のテーブルでも200を返して接続を閉じる", async () => {
    const response = await GET();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ready" });
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    for (const client of [writer, reader]) {
      expect(client.query).toHaveBeenCalledWith("SELECT id FROM reports LIMIT 1");
      expect(client.end).toHaveBeenCalledOnce();
    }
  });

  it.each([
    ["writerの接続失敗", "writer", "connect"],
    ["readerの接続失敗", "reader", "connect"],
    ["テーブル未作成", "writer", "query"],
    ["クエリのタイムアウト", "reader", "query"],
  ] as const)("%sなら503を返し、エラー詳細を公開せず接続を閉じる", async (_, endpoint, operation) => {
    const client = endpoint === "writer" ? writer : reader;
    client[operation].mockRejectedValueOnce(new Error("private database error"));

    const response = await GET();

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ status: "not_ready" });
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(writer.end).toHaveBeenCalledOnce();
    expect(reader.end).toHaveBeenCalledOnce();
  });

  it("TLS設定が不正な場合も503を返す", async () => {
    vi.stubEnv("DB_SSL_MODE", "verify-full");
    vi.stubEnv("DB_SSL_CA_PATH", "");

    const response = await GET();

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ status: "not_ready" });
    expect(Client).not.toHaveBeenCalled();
  });
});
