import { defineConfig } from "drizzle-kit";
import { config } from "dotenv";

config({ path: [".env.local", ".env"] });

const host = process.env.DB_WRITER_ENDPOINT ?? "localhost";
const port = process.env.DB_PORT ?? "5432";
const name = process.env.DB_NAME ?? "app";
const user = process.env.DB_USERNAME ?? "postgres";
const password = process.env.DB_PASSWORD ?? "";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dbCredentials: {
    url: `postgresql://${user}:${encodeURIComponent(password)}@${host}:${port}/${name}`,
  },
});
