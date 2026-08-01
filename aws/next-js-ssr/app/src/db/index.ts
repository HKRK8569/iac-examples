import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema";

// 環境変数はECSタスク定義でSecrets Managerから注入される（infra/modules/app/ecs.tf）
// ローカルでは .env.localを使う
function connectionString(host: string): string {
  const port = process.env.DB_PORT ?? "5432";
  const name = process.env.DB_NAME ?? "app";
  const user = process.env.DB_USERNAME ?? "postgres";
  const password = process.env.DB_PASSWORD ?? "";
  return `postgresql://${user}:${encodeURIComponent(password)}@${host}:${port}/${name}`;
}

const writerPool = new Pool({
  connectionString: connectionString(process.env.DB_WRITER_ENDPOINT ?? "localhost"),
  max: 5,
});

// readerエンドポイントはreaderが0台のとき自動でwriterに向く（multi_az=false時）
const readerPool = new Pool({
  connectionString: connectionString(
    process.env.DB_READER_ENDPOINT ?? process.env.DB_WRITER_ENDPOINT ?? "localhost",
  ),
  max: 5,
});

// 書き込み（INSERT/UPDATE/DELETE）はこちらを使う
export const dbWriter = drizzle(writerPool, { schema });

// 読み取り（SELECT）はこちらを使う
// 注意: multi_az=falseのdevではreaderに書き込めてしまうが、本番(reader有)では
// read-onlyエラーになるため、必ず書き込みはdbWriterを使うこと
export const dbReader = drizzle(readerPool, { schema });
