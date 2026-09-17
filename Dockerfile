FROM node:24-bookworm

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
    tini \
  && rm -rf /var/lib/apt/lists/*

# Cache buster: 2026-09-17 — OpenClaw 2.0 line (2026.9.4)
# Core and the WhatsApp plugin are published separately and are NOT version-locked.
# Verify before bumping:  npm view @openclaw/whatsapp versions --json | tail -20
ARG OPENCLAW_VERSION=2026.9.4
ARG WHATSAPP_VERSION=2026.9.4
RUN npm install -g openclaw@${OPENCLAW_VERSION} clawhub@latest \
  && npm install -g @openclaw/whatsapp@${WHATSAPP_VERSION}

# Backward-compatibility shim for older OPENCLAW_ENTRY values
RUN mkdir -p /openclaw \
  && ln -sfn /usr/local/lib/node_modules/openclaw/dist /openclaw/dist

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm@10 && pnpm install --frozen-lockfile --prod

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
ENV NODE_PATH="/usr/local/lib/node_modules"

EXPOSE 8080

# start-period is deliberately long: the first boot on 7.x runs the legacy
# JSON/JSONL -> SQLite migration against ~1.8 GB of history. Do not let the
# healthcheck kill the container mid-migration.
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["./entrypoint.sh"]
