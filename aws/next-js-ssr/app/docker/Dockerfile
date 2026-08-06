# 後段の COPY --from=builder が参照するステージ名（これがないとbuildが失敗する）
FROM node:24.13.0-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

RUN npm run build

FROM node:24.13.0-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

USER node

# standalone モードはpublicと.next/staticをデフォルトで含まない
COPY --chown=node:node --from=builder /app/.next/standalone ./
COPY --chown=node:node --from=builder /app/.next/static ./.next/static
COPY --chown=node:node --from=builder /app/public ./public

EXPOSE 3000

CMD ["node", "server.js"]
