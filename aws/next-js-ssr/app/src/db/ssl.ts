import { readFileSync } from "node:fs";
import type { ConnectionOptions } from "node:tls";

// localhostでもSSM経由ならTLSが必要なので、接続先から有効・無効を推測しない。
export function databaseSsl(
  host: string,
  env: Partial<NodeJS.ProcessEnv> = process.env,
): false | ConnectionOptions {
  const mode = env.DB_SSL_MODE ?? "disable";
  if (mode === "disable") return false;
  if (mode !== "verify-full") {
    throw new Error("DB_SSL_MODE must be disable or verify-full");
  }
  if (!env.DB_SSL_CA_PATH) {
    throw new Error("DB_SSL_CA_PATH is required for verify-full");
  }

  return {
    ca: readFileSync(env.DB_SSL_CA_PATH, "utf8"),
    rejectUnauthorized: true,
    // SSMトンネルではTCP接続先と証明書の検証先が異なる。
    servername: env.DB_SSL_SERVERNAME || host,
  };
}
