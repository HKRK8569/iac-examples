// S3のオブジェクトキー（例: "images/xxxx.jpg"）から表示URLを作る
// 通常はページと同じCloudFrontドメインを使い、ローカル開発ではCDNドメインを指定できる
export function imageUrl(imageKey: string | null): string | null {
  if (!imageKey) return null;
  const domain = process.env.NEXT_PUBLIC_CDN_DOMAIN;
  return domain ? `https://${domain}/${imageKey}` : `/${imageKey}`;
}
