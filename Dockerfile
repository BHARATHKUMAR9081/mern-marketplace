# MERN Marketplace — Production Dockerfile

```dockerfile
# ============================================================
# MERN Marketplace 2.0 — Multi-stage Production Build
# Runtime: Node 13 (SSR Express server + Socket.io bidding)
# ============================================================

# ------------ STAGE 1: deps ------------
FROM node:13-alpine AS deps
WORKDIR /app

COPY package.json ./
RUN npm install --legacy-peer-deps --no-audit --no-fund

# ------------ STAGE 2: build ------------
FROM node:13-alpine AS build
WORKDIR /app

# Cache manifests + installed deps (incl. devDependencies for webpack/babel)
COPY package.json ./
COPY --from=deps /app/node_modules ./node_modules

# Full source tree (client/, server/, config/, webpack configs, .babelrc, template.js)
COPY . .

# Production bundles: dist/bundle.js (client) + dist/server.generated.js (SSR server)
RUN npm run build

# ------------ STAGE 3: runtime ------------
FROM node:13-alpine AS runtime

# Hardened runtime: non-root user, minimal surface
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Application manifests + production runtime dependencies only
COPY package.json ./
RUN npm install --omit=dev --legacy-peer-deps --no-audit --no-fund \
    && npm cache clean --force

# Compiled server bundle (commonjs2, node-externals -> requires node_modules)
COPY --from=build /app/dist ./dist

# Files required at runtime by the server bundle:
#  - config/config.js        (mongoUri, port, jwtSecret, stripe keys)
#  - template.js             (SSR HTML shell, resolved via process.cwd())
#  - client/assets/images    (default.png for shop/product/auction fallback photos)
COPY --from=build /app/config ./config
COPY --from=build /app/template.js ./template.js
COPY --from=build /app/client/assets ./client/assets

# Runtime configuration (overridable per-environment)
ENV NODE_ENV=production \
    PORT=8000 \
    MONGO_URI="" \
    JWT_SECRET="" \
    STRIPE_TEST_SECRET_KEY=""

EXPOSE 8000

# Ownership for non-root execution
RUN chown -R appuser:appgroup /app
USER appuser

# HTTP + WebSocket (Socket.io) on the same long-lived process
CMD ["node", "./dist/server.generated.js"]