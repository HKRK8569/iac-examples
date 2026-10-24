import { randomUUID } from "node:crypto";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { NextRequest, NextResponse } from "next/server";

// 認証情報はECSタスクロールから自動取得される（ローカルではprofile/環境変数）
const s3 = new S3Client({
  region: process.env.AWS_REGION ?? "ap-northeast-1",
});

const ALLOWED_CONTENT_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
};

// 画像アップロード用の署名付きURLを発行する
// ALB/Next.jsのボディサイズ制限を避けるため、ブラウザがこのURLへ直接PutObjectする
export async function POST(req: NextRequest) {
  const bucket = process.env.IMAGES_BUCKET_NAME;
  if (!bucket) {
    return NextResponse.json(
      { message: "IMAGES_BUCKET_NAMEが設定されていません" },
      { status: 500 },
    );
  }

  const json = await req.json().catch(() => null);
  const contentType = json?.contentType;
  const ext = typeof contentType === "string" ? ALLOWED_CONTENT_TYPES[contentType] : undefined;
  if (!ext) {
    return NextResponse.json(
      { message: "jpeg / png / webp / gif のみアップロードできます" },
      { status: 400 },
    );
  }

  // CloudFrontの /images/* パスパターンがそのままS3のキーになるため images/ プレフィックスを付ける
  const imageKey = `images/${randomUUID()}.${ext}`;

  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({
      Bucket: bucket,
      Key: imageKey,
      ContentType: contentType,
    }),
    { expiresIn: 300 },
  );

  return NextResponse.json({ uploadUrl, imageKey });
}
