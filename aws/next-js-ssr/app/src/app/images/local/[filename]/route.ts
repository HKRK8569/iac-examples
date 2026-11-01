import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { IMAGE_CONTENT_TYPES, MAX_IMAGE_SIZE } from "../../../../lib/image";
import { localImageDirectory, usesLocalImages } from "../../../../lib/image-storage";

export const runtime = "nodejs";

type Context = { params: Promise<{ filename: string }> };

function contentTypeFor(filename: string): string | undefined {
  const match = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.(jpg|png|webp|gif)$/.exec(filename);
  return match && Object.entries(IMAGE_CONTENT_TYPES).find(([, ext]) => ext === match[1])?.[0] || undefined;
}

export async function PUT(request: Request, { params }: Context) {
  const { filename } = await params;
  const contentType = contentTypeFor(filename);
  if (!usesLocalImages() || !contentType) {
    return new Response(null, { status: 404 });
  }
  if (request.headers.get("content-type") !== contentType) {
    return Response.json({ message: "画像の種類が一致しません" }, { status: 400 });
  }
  if (Number(request.headers.get("content-length")) > MAX_IMAGE_SIZE) {
    return Response.json({ message: "画像は10MB以下にしてください" }, { status: 413 });
  }

  const reader = request.body?.getReader();
  if (!reader) {
    return Response.json({ message: "画像が空です" }, { status: 400 });
  }

  try {
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_IMAGE_SIZE) {
        await reader.cancel();
        return Response.json({ message: "画像は10MB以下にしてください" }, { status: 413 });
      }
      chunks.push(value);
    }
    if (size === 0) {
      return Response.json({ message: "画像が空です" }, { status: 400 });
    }

    const directory = localImageDirectory();
    await mkdir(directory, { recursive: true });
    await writeFile(join(directory, filename), Buffer.concat(chunks, size), { flag: "wx" });
    return new Response(null, { status: 201 });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") {
      return Response.json({ message: "この画像は既に保存されています" }, { status: 409 });
    }
    console.error("ローカル画像の保存に失敗しました", error);
    return Response.json({ message: "画像の保存に失敗しました" }, { status: 500 });
  } finally {
    reader.releaseLock();
  }
}

export async function GET(_request: Request, { params }: Context) {
  const { filename } = await params;
  const contentType = contentTypeFor(filename);
  if (!usesLocalImages() || !contentType) {
    return new Response(null, { status: 404 });
  }

  try {
    const image = await readFile(join(localImageDirectory(), filename));
    return new Response(new Uint8Array(image), {
      headers: {
        "Content-Type": contentType,
        "Content-Length": String(image.byteLength),
        "Cache-Control": "public, max-age=31536000, immutable",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return new Response(null, { status: 404 });
    }
    console.error("ローカル画像の読み込みに失敗しました", error);
    return Response.json({ message: "画像の読み込みに失敗しました" }, { status: 500 });
  }
}
