import "server-only";
import { Client } from "pg";
import { databaseConnectionConfig } from "./config";

async function checkConnection(endpoint: "writer" | "reader"): Promise<void> {
  // 確認専用の短い接続を使い、通常のDB処理のタイムアウト・プールに影響させない。
  const client = new Client({
    ...databaseConnectionConfig(endpoint),
    connectionTimeoutMillis: 2000,
    statement_timeout: 2000,
    query_timeout: 2000,
  });
  client.on("error", (error) => {
    console.error(`Database readiness connection error (${endpoint})`, error);
  });

  try {
    await client.connect();
    // 0件でも成功。接続確認だけのSELECT 1では検出できないテーブル未作成も検出する。
    await client.query("SELECT id FROM reports LIMIT 1");
  } finally {
    // 接続失敗・クエリのタイムアウト時も確認用の接続を残さない。
    await client.end();
  }
}

export async function checkDatabaseReadiness(): Promise<void> {
  await Promise.all([checkConnection("writer"), checkConnection("reader")]);
}
