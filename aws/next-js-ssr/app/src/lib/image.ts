export const LOCAL_IMAGE_PREFIX = "images/local/";
export const MAX_IMAGE_SIZE = 10 * 1024 * 1024;
export const IMAGE_CONTENT_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
};

// ローカル画像は同じサーバーから、S3画像はCloudFrontから表示する。
export function imageUrl(imageKey: string | null): string | null {
  if (!imageKey) return null;
  if (imageKey.startsWith(LOCAL_IMAGE_PREFIX)) return `/${imageKey}`;
  const domain = process.env.NEXT_PUBLIC_CDN_DOMAIN;
  return domain ? `https://${domain}/${imageKey}` : `/${imageKey}`;
}
