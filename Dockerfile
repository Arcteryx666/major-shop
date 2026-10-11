# syntax=docker/dockerfile:1
# MAJOR SHOP: один образ = API + Telegram-бот + планировщик + собранный Mini App.

FROM node:22-bookworm-slim AS base
# openssl нужен движку миграций Prisma
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# ---------- зависимости ----------
FROM base AS deps
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/server/package.json apps/server/
COPY apps/web/package.json apps/web/
RUN npm ci

# ---------- сборка ----------
FROM deps AS build
COPY tsconfig.base.json ./
COPY packages ./packages
COPY apps ./apps
RUN npm run build \
 && npm prune --omit=dev \
 && npx prisma generate --schema apps/server/prisma/schema.prisma

# ---------- запуск ----------
FROM base AS runtime
ENV NODE_ENV=production \
    PORT=3000 \
    WEB_DIST_DIR=/app/apps/web/dist
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/packages ./packages
COPY --from=build /app/apps/server/package.json ./apps/server/
COPY --from=build /app/apps/server/dist ./apps/server/dist
COPY --from=build /app/apps/server/prisma ./apps/server/prisma
COPY --from=build /app/apps/web/dist ./apps/web/dist
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
WORKDIR /app/apps/server
# Миграции применяются при каждом старте (безопасно: применяются только новые).
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/index.js"]
