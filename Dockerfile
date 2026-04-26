FROM node:22-bookworm
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    perl \
    procps \
    python3 \
    build-essential \
    zip \
  && rm -rf /var/lib/apt/lists/*
RUN npm install -g openclaw@2026.4.11 clawhub@latest

# Patch the bundled Baileys auth payload bugs in OpenClaw's session-*.js
# OpenClaw bundles Baileys into dist/session-*.js at build time, so patching
# the @whiskeysockets/baileys node_modules install has no runtime effect.
# Two surgical fixes to the bundled generateLoginNode:
#   1. passive: true -> passive: false  (server rejects passive listeners with device_removed)
#   2. remove lidDbMigrated: false      (non-spec field, server rejects payloads containing it)
RUN SESSION_FILE=$(find /usr/local/lib/node_modules/openclaw/dist -maxdepth 1 -name "session-*.js" | head -1) \
  && if [ -z "$SESSION_FILE" ]; then echo "ERROR: session-*.js not found in openclaw/dist" && exit 1; fi \
  && echo "Patching $SESSION_FILE" \
  && perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)passive:\s*true,/\1passive: false,/' "$SESSION_FILE" \
  && perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)\s*lidDbMigrated:\s*false,?\n?//' "$SESSION_FILE" \
  && if grep -q "lidDbMigrated: false" "$SESSION_FILE"; then echo "ERROR: lidDbMigrated: false still present"; exit 1; fi \
  && PASSIVE_TRUE_COUNT=$(grep -c "passive: true" "$SESSION_FILE" || true) \
  && PASSIVE_FALSE_COUNT=$(grep -c "passive: false" "$SESSION_FILE" || true) \
  && echo "After patch: passive: true count=$PASSIVE_TRUE_COUNT, passive: false count=$PASSIVE_FALSE_COUNT" \
  && if [ "$PASSIVE_TRUE_COUNT" != "0" ]; then echo "ERROR: still found passive: true (expected 0)"; exit 1; fi \
  && echo "Bundle patches applied successfully"

# Backward-compatibility shim for older OPENCLAW_ENTRY values.
RUN mkdir -p /openclaw \
  && ln -sfn /usr/local/lib/node_modules/openclaw/dist /openclaw/dist
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod
COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh
RUN useradd -m -s /bin/bash openclaw \
  && chown -R openclaw:openclaw /app \
  && mkdir -p /data && chown openclaw:openclaw /data \
  && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew
USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
ENV PORT=8080
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1
USER root
ENTRYPOINT ["./entrypoint.sh"]
