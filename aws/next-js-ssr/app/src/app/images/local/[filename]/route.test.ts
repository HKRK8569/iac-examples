import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import { MAX_IMAGE_SIZE, imageUrl } from "../../../../lib/image";
import { GET, PUT } from "./route";

const filename = "b5c51ad1-41a0-4f86-a69e-78a336ba7978.png";
const bytes = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=", "base64");
let directory: string;

function context(name = filename) {
  return { params: Promise.resolve({ filename: name }) };
}

function upload(body: Uint8Array = bytes, contentType = "image/png") {
  return new Request(`http://localhost/images/local/${filename}`, {
    method: "PUT",
    headers: { "Content-Type": contentType },
    body: new Uint8Array(body),
  });
}

beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), "local-images-test-"));
  vi.spyOn(process, "cwd").mockReturnValue(directory);
  vi.stubEnv("IMAGE_STORAGE", "local");
});

afterEach(async () => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  // このテストが作った一時ディレクトリだけを削除する。
  expect(dirname(resolve(directory))).toBe(resolve(tmpdir()));
  expect(directory.split(/[\\/]/).at(-1)).toMatch(/^local-images-test-/);
  await rm(directory, { recursive: true, force: true });
});

describe("ローカル画像の保存と表示", () => {
  it("画像をディスクに保存し、別のGETリクエストでも同じ内容を返す", async () => {
    expect((await PUT(upload(), context())).status).toBe(201);
    expect(await readFile(join(directory, ".local-images", filename))).toEqual(bytes);

    const response = await GET(new Request("http://localhost"), context());
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("image/png");
    expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(Buffer.from(await response.arrayBuffer())).toEqual(bytes);
  });

  it("同じ画像の上書きを拒否し、保存済みの内容を保つ", async () => {
    await PUT(upload(), context());
    expect((await PUT(upload(Buffer.from("replacement")), context())).status).toBe(409);
    expect(await readFile(join(directory, ".local-images", filename))).toEqual(bytes);
  });

  it("S3モードではローカルファイルを保存・公開しない", async () => {
    await PUT(upload(), context());
    vi.stubEnv("IMAGE_STORAGE", "s3");
    expect((await PUT(upload(), context())).status).toBe(404);
    expect((await GET(new Request("http://localhost"), context())).status).toBe(404);
  });

  it.each(["../private.png", "not-an-id.png", "b5c51ad1-41a0-4f86-a69e-78a336ba7978.svg"])("不正なファイル名 %s を拒否する", async (name) => {
    expect((await PUT(upload(), context(name))).status).toBe(404);
    expect((await GET(new Request("http://localhost"), context(name))).status).toBe(404);
  });

  it("拡張子と異なるContent-Typeと空の画像を拒否する", async () => {
    expect((await PUT(upload(bytes, "image/jpeg"), context())).status).toBe(400);
    expect((await PUT(upload(new Uint8Array()), context())).status).toBe(400);
  });

  it("Content-Lengthがなくても10MBを超える画像を拒否する", async () => {
    const response = await PUT(upload(new Uint8Array(MAX_IMAGE_SIZE + 1)), context());
    expect(response.status).toBe(413);
    await expect(readFile(join(directory, ".local-images", filename))).rejects.toMatchObject({ code: "ENOENT" });
  });

  it("存在しない画像には404を返す", async () => {
    expect((await GET(new Request("http://localhost"), context())).status).toBe(404);
  });

  it("CDNドメイン設定中もローカル画像はローカルから表示する", () => {
    vi.stubEnv("NEXT_PUBLIC_CDN_DOMAIN", "example.cloudfront.net");
    expect(imageUrl(`images/local/${filename}`)).toBe(`/images/local/${filename}`);
    expect(imageUrl(`images/${filename}`)).toBe(`https://example.cloudfront.net/images/${filename}`);
  });
});
