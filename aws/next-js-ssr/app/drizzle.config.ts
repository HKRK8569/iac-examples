import { defineConfig } from "drizzle-kit";
import { config } from "dotenv";
import { databaseSsl } from "./src/db/ssl";

config({ path: [".env.local", ".env"] });

const host = process.env.DB_WRITER_ENDPOINT ?? "localhost";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dbCredentials: {
    host,
    port: Number(process.env.DB_PORT ?? "5432"),
    database: process.env.DB_NAME ?? "app",
    user: process.env.DB_USERNAME ?? "postgres",
    password: process.env.DB_PASSWORD ?? "",
    ssl: databaseSsl(host),
  },
});
