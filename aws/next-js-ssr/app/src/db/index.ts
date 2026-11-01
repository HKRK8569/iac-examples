// クライアントコンポーネントから誤ってimportされた場合にビルドエラーにする
import "server-only";
import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema";
import { databaseConnectionConfig } from "./config";

// 環境変数はECSタスク定義でSecrets Managerから注入される（infra/modules/app/ecs.tf）
// ローカルでは .env.localを使う

const writerPool = new Pool({
  ...databaseConnectionConfig("writer"),
  max: 5,
});

// readerエンドポイントはreaderが0台のとき自動でwriterに向く（multi_az=false時）
const readerPool = new Pool({
  ...databaseConnectionConfig("reader"),
  max: 5,
});

// 書き込み（INSERT/UPDATE/DELETE）はこちらを使う
export const dbWriter = drizzle(writerPool, { schema });

// 読み取り（SELECT）はこちらを使う
// 注意: multi_az=falseのdevではreaderに書き込めてしまうが、本番(reader有)では
// read-onlyエラーになるため、必ず書き込みはdbWriterを使うこと
export const dbReader = drizzle(readerPool, { schema });
