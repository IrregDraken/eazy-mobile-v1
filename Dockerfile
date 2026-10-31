FROM node:22-alpine AS build
WORKDIR /app/backend

COPY backend/package.json backend/package-lock.json ./
# Keep Railway builds resilient to a stale committed lockfile while dependency
# metadata is being synchronized. The generated lock is reused by the runtime stage.
RUN npm install --package-lock-only --ignore-scripts && npm ci

COPY backend/tsconfig.json ./
COPY backend/src ./src
COPY backend/migrations ./migrations
RUN npm run build

FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app/backend

COPY backend/package.json backend/package-lock.json ./
COPY --from=build /app/backend/package-lock.json ./package-lock.json
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=build /app/backend/dist ./dist
COPY --from=build /app/backend/migrations ./migrations

EXPOSE 3000
CMD ["node", "dist/src/server.js"]
