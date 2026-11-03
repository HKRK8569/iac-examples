import "server-only";
import type { ClientConfig } from "pg";
import { databaseSsl } from "./ssl";

// アプリの接続プールとreadiness確認で同じ接続情報・TLS設定を使う。
export function databaseConnectionConfig(endpoint: "writer" | "reader"): ClientConfig {
  const writerHost = process.env.DB_WRITER_ENDPOINT ?? "localhost";
  const host = endpoint === "reader"
    ? process.env.DB_READER_ENDPOINT ?? writerHost
    : writerHost;
  const port = process.env.DB_PORT ?? "5432";
  const name = process.env.DB_NAME ?? "app";
  const user = process.env.DB_USERNAME ?? "postgres";
  const password = process.env.DB_PASSWORD ?? "";

  return {
    connectionString: `postgresql://${user}:${encodeURIComponent(password)}@${host}:${port}/${name}`,
    ssl: databaseSsl(host),
  };
}
