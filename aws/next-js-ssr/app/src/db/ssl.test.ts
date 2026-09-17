import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { databaseSsl } from "./ssl";

const directory = mkdtempSync(join(tmpdir(), "database-ssl-"));
const caPath = join(directory, "ca.pem");
writeFileSync(caPath, "test-ca");
afterAll(() => rmSync(directory, { recursive: true, force: true }));

describe("DB接続のTLS設定", () => {
  it("ローカル開発ではTLSを無効にする", () => {
    expect(databaseSsl("localhost", {})).toBe(false);
    expect(databaseSsl("localhost", { DB_SSL_MODE: "disable" })).toBe(false);
  });

  it("未対応のモードやCAファイルの未指定・読み込み失敗をエラーにする", () => {
    expect(() => databaseSsl("db.example", { DB_SSL_MODE: "require" })).toThrow();
    expect(() => databaseSsl("db.example", { DB_SSL_MODE: "verify-full" })).toThrow();
    expect(() => databaseSsl("db.example", {
      DB_SSL_MODE: "verify-full", DB_SSL_CA_PATH: join(directory, "missing.pem"),
    })).toThrow();
  });

  it("直接接続では指定したCAと各エンドポイント名を検証する設定を返す", () => {
    for (const host of ["writer.example", "reader.example"]) {
      expect(databaseSsl(host, {
        DB_SSL_MODE: "verify-full", DB_SSL_CA_PATH: caPath,
      })).toEqual({ ca: "test-ca", rejectUnauthorized: true, servername: host });
    }
  });

  it("トンネル経由でもTLSを有効にしAuroraの名前を検証する設定を返す", () => {
    expect(databaseSsl("127.0.0.1", {
      DB_SSL_MODE: "verify-full",
      DB_SSL_CA_PATH: caPath,
      DB_SSL_SERVERNAME: "writer.example",
    })).toEqual({
      ca: "test-ca", rejectUnauthorized: true, servername: "writer.example",
    });
  });
});
