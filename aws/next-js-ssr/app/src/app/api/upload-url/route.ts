import { randomUUID } from "node:crypto";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { NextRequest, NextResponse } from "next/server";
import { IMAGE_CONTENT_TYPES, LOCAL_IMAGE_PREFIX } from "../../../lib/image";
import { usesLocalImages } from "../../../lib/image-storage";

// 認証情報はECSタスクロールから自動取得される（ローカルではprofile/環境変数）
const s3 = new S3Client({
  region: process.env.AWS_REGION ?? "ap-northeast-1",
});

// ローカル保存用URL、またはS3に直接PUTするための署名付きURLを発行する。
export async function POST(req: NextRequest) {
  const json = await req.json().catch(() => null);
  const contentType = json?.contentType;
  const ext = typeof contentType === "string" && Object.hasOwn(IMAGE_CONTENT_TYPES, contentType)
    ? IMAGE_CONTENT_TYPES[contentType]
    : undefined;
  if (!ext) {
    return NextResponse.json(
      { message: "jpeg / png / webp / gif のみアップロードできます" },
      { status: 400 },
    );
  }

  if (usesLocalImages()) {
    const imageKey = `${LOCAL_IMAGE_PREFIX}${randomUUID()}.${ext}`;
    return NextResponse.json({ uploadUrl: `/${imageKey}`, imageKey });
  }

  const bucket = process.env.IMAGES_BUCKET_NAME;
  if (!bucket) {
    return NextResponse.json(
      { message: "IMAGES_BUCKET_NAMEが設定されていません" },
      { status: 500 },
    );
  }

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
