import { defineConfig } from "tsup";

export default defineConfig({
  entry: { worker: "src/index.ts" },
  outDir: "dist",
  format: ["esm"],
  outExtension: () => ({ js: ".mjs" }),
});
