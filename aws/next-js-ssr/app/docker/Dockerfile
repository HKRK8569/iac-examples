# 後段の COPY --from=builder が参照するステージ名（これがないとbuildが失敗する）
FROM node:24.13.0-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# AWS公開CAをビルド時に取得し、実行時のネットワーク取得を不要にする
RUN mkdir -p /rds-certs && wget -O /rds-certs/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

RUN npm run build

FROM node:24.13.0-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --chown=node:node --from=builder /rds-certs/global-bundle.pem /app/certs/global-bundle.pem

USER node

# standalone モードはpublicと.next/staticをデフォルトで含まない
COPY --chown=node:node --from=builder /app/.next/standalone ./
COPY --chown=node:node --from=builder /app/.next/static ./.next/static
COPY --chown=node:node --from=builder /app/public ./public

EXPOSE 3000

CMD ["node", "server.js"]
