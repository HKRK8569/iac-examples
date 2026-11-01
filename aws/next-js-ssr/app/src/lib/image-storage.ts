import "server-only";
import { join } from "node:path";

export function usesLocalImages(): boolean {
  const storage = process.env.IMAGE_STORAGE;
  return storage === "local" || (!storage && process.env.NODE_ENV === "development");
}

export function localImageDirectory(): string {
  return join(process.cwd(), ".local-images");
}
