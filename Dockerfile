# Alpine Linux base image — small, open source (Node.js is MIT, Alpine is MIT/BSD)
FROM node:22-alpine AS deps

WORKDIR /app
COPY app/package.json app/package-lock.json* ./
# npm ci when a lockfile exists, otherwise fall back to install
RUN if [ -f package-lock.json ]; then \
      npm ci --omit=dev; \
    else \
      npm install --omit=dev --no-audit --no-fund; \
    fi \
    && npm cache clean --force


FROM node:22-alpine AS runtime

# tini reaps zombies and forwards SIGTERM so Kubernetes can stop the pod cleanly
RUN apk add --no-cache tini

ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY app/package.json ./package.json
COPY app/server.js ./server.js
COPY app/public ./public

# node:alpine ships an unprivileged "node" user (uid 1000)
USER node

EXPOSE 3000

LABEL org.opencontainers.image.title="hello-world-frontend" \
      org.opencontainers.image.description="Node.js Hello World front end" \
      org.opencontainers.image.licenses="MIT"

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
