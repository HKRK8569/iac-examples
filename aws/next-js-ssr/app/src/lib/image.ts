// S3のオブジェクトキー（例: "images/xxxx.jpg"）からCloudFront経由の表示URLを作る
// CDNドメイン未設定（ローカル開発等）や画像なしの場合はnull
export function imageUrl(imageKey: string | null): string | null {
  const domain = process.env.NEXT_PUBLIC_CDN_DOMAIN;
  if (!imageKey || !domain) return null;
  return `https://${domain}/${imageKey}`;
}
