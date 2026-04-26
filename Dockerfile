FROM node:22-bookworm

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    procps \
    python3 \
    build-essential \
    zip \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@2026.4.11 clawhub@latest

# Replace bundled Baileys with patched fork (rossodwyer/Baileys @ 9106cf7e5f)
# Fixes WhatsApp auth payload bugs: passive flag and non-spec lidDbMigrated field.
RUN BAILEYS_PATH=$(find /usr/local/lib/node_modules/openclaw -type d -path '*/node_modules/@whiskeysockets/baileys' | head -1) \
  && if [ -z "$BAILEYS_PATH" ]; then echo "ERROR: Could not find Baileys install" && exit 1; fi \
  && echo "Replacing Baileys at $BAILEYS_PATH" \
  && rm -rf "$BAILEYS_PATH" \
  && mkdir -p "$BAILEYS_PATH" \
  && curl -fsSL https://github.com/rossodwyer/Baileys/archive/40510ed8d6.tar.gz \
    | tar xz --strip-components=1 -C "$BAILEYS_PATH" \
  && grep -q "passive: false" "$BAILEYS_PATH/lib/Utils/validate-connection.js" \
  && grep -q "baileys-debug.log" "$BAILEYS_PATH/lib/Socket/Client/websocket.js" \
  && ! grep -q "lidDbMigrated" "$BAILEYS_PATH/lib/Utils/validate-connection.js" \
  && grep -q "WHATSAPP_PROXY_URL" "$BAILEYS_PATH/lib/Socket/Client/websocket.js" \
  && echo "Baileys patch verified at $BAILEYS_PATH"

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
