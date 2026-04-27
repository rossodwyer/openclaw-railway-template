#!/bin/bash
set -e

SESSION_FILE=$(find /usr/local/lib/node_modules/openclaw/dist -maxdepth 1 -name "session-*.js" | head -1)

if [ -z "$SESSION_FILE" ]; then
  echo "ERROR: session-*.js not found in openclaw/dist"
  exit 1
fi

DIAG=/usr/local/lib/node_modules/openclaw/dist/PATCH_DIAG.txt
echo "=== patch-bundle.sh diagnostic log ===" > "$DIAG"
echo "Session file: $SESSION_FILE" >> "$DIAG"
echo "" >> "$DIAG"

dump_counts() {
  local label="$1"
  echo "[$label]" >> "$DIAG"
  echo "  agent: this.config.agent : $(grep -c 'agent: this.config.agent' "$SESSION_FILE")" >> "$DIAG"
  echo "  lidDbMigrated: false     : $(grep -c 'lidDbMigrated: false' "$SESSION_FILE")" >> "$DIAG"
  echo "  passive: true            : $(grep -c 'passive: true' "$SESSION_FILE")" >> "$DIAG"
  echo "  passive: false           : $(grep -c 'passive: false' "$SESSION_FILE")" >> "$DIAG"
}

dump_counts "BEFORE"

# Patch 1: passive: true -> passive: false in generateLoginNode
perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)passive:\s*true,/\1passive: false,/' "$SESSION_FILE"
dump_counts "AFTER passive patch"

# Patch 2: remove lidDbMigrated: false in generateLoginNode
perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)\s*lidDbMigrated:\s*false,?\n?//' "$SESSION_FILE"
dump_counts "AFTER lidDbMigrated patch"

# Patch 3: inject WHATSAPP_PROXY_URL agent into WebSocketClient.connect()
perl -i -pe 's|agent: this\.config\.agent|agent: this.config.agent || (process.env.WHATSAPP_PROXY_URL && /whatsapp\.(net|com)/i.test(this.url) ? new (require("https-proxy-agent").HttpsProxyAgent)(process.env.WHATSAPP_PROXY_URL) : void 0)|' "$SESSION_FILE"
dump_counts "AFTER proxy patch"

echo "" >> "$DIAG"
echo "=== Final state ===" >> "$DIAG"
echo "WHATSAPP_PROXY_URL refs : $(grep -c 'WHATSAPP_PROXY_URL' "$SESSION_FILE")" >> "$DIAG"
echo "" >> "$DIAG"

# Print diagnostic to stdout so the build log captures it
cat "$DIAG"

# Verify final state
if grep -q "lidDbMigrated: false" "$SESSION_FILE"; then
  echo "FAIL: lidDbMigrated still present after patch"
  exit 1
fi
if [ "$(grep -c 'passive: true' "$SESSION_FILE")" != "0" ]; then
  echo "FAIL: passive: true still present"
  exit 1
fi
if [ "$(grep -c 'WHATSAPP_PROXY_URL' "$SESSION_FILE")" -lt "1" ]; then
  echo "FAIL: WHATSAPP_PROXY_URL injection didn't apply"
  exit 1
fi

echo "All patches applied successfully"
