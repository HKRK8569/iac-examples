import { NextRequest } from "next/server";
import { afterEach, describe, expect, it, vi } from "vitest";

const { getSignedUrl } = vi.hoisted(() => ({ getSignedUrl: vi.fn() }));
vi.mock("@aws-sdk/s3-request-presigner", () => ({ getSignedUrl }));
vi.mock("server-only", () => ({}));

import { POST } from "./route";

function request(contentType: string) {
  return new NextRequest("http://localhost/api/upload-url", {
    method: "POST",
    body: JSON.stringify({ contentType }),
  });
}

afterEach(() => {
  vi.unstubAllEnvs();
  vi.clearAllMocks();
});

describe("画像アップロード先の切り替え", () => {
  it("ローカルモードではAWS認証・S3バケットなしでアップロード先を返す", async () => {
    vi.stubEnv("IMAGE_STORAGE", "local");
    vi.stubEnv("IMAGES_BUCKET_NAME", "");
    const response = await POST(request("image/png"));
    const result = await response.json();
    expect(response.status).toBe(200);
    expect(result.imageKey).toMatch(/^images\/local\/[0-9a-f-]+\.png$/);
    expect(result.uploadUrl).toBe(`/${result.imageKey}`);
    expect(getSignedUrl).not.toHaveBeenCalled();
  });

  it("設定未指定の開発環境でもローカルに保存する", async () => {
    vi.stubEnv("IMAGE_STORAGE", "");
    vi.stubEnv("NODE_ENV", "development");
    const result = await (await POST(request("image/jpeg"))).json();
    expect(result.imageKey).toMatch(/^images\/local\/.+\.jpg$/);
  });

  it("本番のデフォルトはS3署名付きURLを発行する", async () => {
    vi.stubEnv("IMAGE_STORAGE", "");
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("IMAGES_BUCKET_NAME", "test-images");
    getSignedUrl.mockResolvedValue("https://test-images.s3.amazonaws.com/signed");
    const result = await (await POST(request("image/webp"))).json();
    expect(result.uploadUrl).toBe("https://test-images.s3.amazonaws.com/signed");
    expect(result.imageKey).toMatch(/^images\/[0-9a-f-]+\.webp$/);
    expect(getSignedUrl.mock.calls[0][1].input.Bucket).toBe("test-images");
  });

  it.each(["image/svg+xml", "application/octet-stream", "constructor"])("未対応の種類 %s を拒否する", async (contentType) => {
    vi.stubEnv("IMAGE_STORAGE", "local");
    expect((await POST(request(contentType))).status).toBe(400);
  });
});
