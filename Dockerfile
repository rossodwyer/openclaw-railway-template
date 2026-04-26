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

  # Force rebuild from this point: 2026-04-26 fresh
RUN npm install -g openclaw@2026.4.11 clawhub@latest

# Patch the bundled Baileys auth payload bugs in OpenClaw's session-*.js
# Two surgical fixes to the bundled generateLoginNode:
#   1. passive: true -> passive: false  (server rejects passive listeners with device_removed)
#   2. remove lidDbMigrated: false      (non-spec field, server rejects payloads containing it)
RUN SESSION_FILE=$(find /usr/local/lib/node_modules/openclaw/dist -maxdepth 1 -name "session-*.js" | head -1) \
  && if [ -z "$SESSION_FILE" ]; then echo "ERROR: session-*.js not found in openclaw/dist" && exit 1; fi \
  && BEFORE_AGENT=$(grep -c 'agent: this\.config\.agent' "$SESSION_FILE") \
  && BEFORE_LID=$(grep -c 'lidDbMigrated: false' "$SESSION_FILE") \
  && BEFORE_PT=$(grep -c 'passive: true' "$SESSION_FILE") \
  && BEFORE_PF=$(grep -c 'passive: false' "$SESSION_FILE") \
  && perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)passive:\s*true,/\1passive: false,/' "$SESSION_FILE" \
  && AFTER_PASSIVE_AGENT=$(grep -c 'agent: this\.config\.agent' "$SESSION_FILE") \
  && AFTER_PASSIVE_LID=$(grep -c 'lidDbMigrated: false' "$SESSION_FILE") \
  && AFTER_PASSIVE_PT=$(grep -c 'passive: true' "$SESSION_FILE") \
  && AFTER_PASSIVE_PF=$(grep -c 'passive: false' "$SESSION_FILE") \
  && perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)\s*lidDbMigrated:\s*false,?\n?//' "$SESSION_FILE" \
  && AFTER_LID_AGENT=$(grep -c 'agent: this\.config\.agent' "$SESSION_FILE") \
  && AFTER_LID_LID=$(grep -c 'lidDbMigrated: false' "$SESSION_FILE") \
  && AFTER_LID_PT=$(grep -c 'passive: true' "$SESSION_FILE") \
  && AFTER_LID_PF=$(grep -c 'passive: false' "$SESSION_FILE") \
  && echo "DIAGNOSTIC|BEFORE|agent=$BEFORE_AGENT|lid=$BEFORE_LID|pt=$BEFORE_PT|pf=$BEFORE_PF|AFTERPASSIVE|agent=$AFTER_PASSIVE_AGENT|lid=$AFTER_PASSIVE_LID|pt=$AFTER_PASSIVE_PT|pf=$AFTER_PASSIVE_PF|AFTERLID|agent=$AFTER_LID_AGENT|lid=$AFTER_LID_LID|pt=$AFTER_LID_PT|pf=$AFTER_LID_PF" \
  && if [ "$AFTER_LID_AGENT" -lt "1" ]; then echo "ERROR: agent line was destroyed by patches"; exit 1; fi \
  && echo "Auth payload patches applied successfully"

# Inject WHATSAPP_PROXY_URL support into the bundled Baileys WebSocketClient.connect()
# Replaces the agent line in connect() with a fallback that wraps WhatsApp-bound
# connections in an HttpsProxyAgent when WHATSAPP_PROXY_URL is set.
# Only that one call site is affected (other WebSocket users in the bundle don't
# use the "agent: this.config.agent" pattern).
RUN SESSION_FILE=$(find /usr/local/lib/node_modules/openclaw/dist -maxdepth 1 -name "session-*.js" | head -1) \
  && BEFORE_COUNT=$(grep -c "agent: this\.config\.agent" "$SESSION_FILE" || true) \
  && echo "Sites with 'agent: this.config.agent': $BEFORE_COUNT (expecting 1)" \
  && if [ "$BEFORE_COUNT" != "1" ]; then echo "ERROR: expected exactly 1 patch site, found $BEFORE_COUNT" && exit 1; fi \
  && perl -i -pe 's|agent: this\.config\.agent|agent: this.config.agent \|\| (process.env.WHATSAPP_PROXY_URL \&\& /whatsapp\\.(net\|com)/i.test(this.url) ? new (require("https-proxy-agent").HttpsProxyAgent)(process.env.WHATSAPP_PROXY_URL) : void 0)|' "$SESSION_FILE" \
  && AFTER_COUNT=$(grep -c "WHATSAPP_PROXY_URL" "$SESSION_FILE" || true) \
  && echo "WHATSAPP_PROXY_URL references in bundle: $AFTER_COUNT (expecting >= 1)" \
  && if [ "$AFTER_COUNT" -lt "1" ]; then echo "ERROR: bundle proxy patch did not apply" && exit 1; fi \
  && echo "Bundle proxy patch applied successfully"

# https-proxy-agent needs to be globally installed so the bundled require() can resolve it
RUN npm install -g https-proxy-agent@^7.0.0

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
ENV NODE_PATH="/usr/local/lib/node_modules"
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1
USER root
ENTRYPOINT ["./entrypoint.sh"]
