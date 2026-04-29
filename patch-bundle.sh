#!/bin/bash
set -x

echo "=== patch-bundle.sh START ==="

# Find the actual Baileys bundle (the one containing 'agent: this.config.agent')
SESSION_FILE=$(grep -l "agent: this\.config\.agent" /usr/local/lib/node_modules/openclaw/dist/session-*.js 2>/dev/null | head -1)

if [ -z "$SESSION_FILE" ]; then
  echo "ERROR: Could not find session-*.js containing 'agent: this.config.agent'"
  ls -la /usr/local/lib/node_modules/openclaw/dist/session-*.js | head -10
  exit 1
fi

echo "SESSION_FILE: $SESSION_FILE"
echo "File size: $(stat -c%s "$SESSION_FILE") bytes"

dump_counts() {
  echo "--- counts: $1 ---"
  echo "agent: this.config.agent: $(grep -c 'agent: this.config.agent' "$SESSION_FILE")"
  echo "lidDbMigrated: false: $(grep -c 'lidDbMigrated: false' "$SESSION_FILE")"
  echo "passive: true: $(grep -c 'passive: true' "$SESSION_FILE")"
  echo "passive: false: $(grep -c 'passive: false' "$SESSION_FILE")"
  echo "WHATSAPP_PROXY_URL: $(grep -c 'WHATSAPP_PROXY_URL' "$SESSION_FILE")"
}

dump_counts "BEFORE"

echo "=== Patch 1: passive ==="
perl -i -pe 's/passive: true,$/passive: false,/' "$SESSION_FILE"
echo "perl rc=$?"
dump_counts "AFTER patch 1"

echo "=== Patch 2: lidDbMigrated ==="
perl -i -ne 'print unless /^\s*lidDbMigrated:\s*false\s*,?\s*$/' "$SESSION_FILE"
echo "perl rc=$?"
dump_counts "AFTER patch 2"

echo "=== Patch 3: proxy injection ==="
python3 /tmp/proxy-patch.py "$SESSION_FILE"
echo "python rc=$?"
dump_counts "AFTER patch 3"

echo "=== Patch 4: noise.finishInit await removal ==="
BEFORE_AWAIT=$(grep -c "await noise\.finishInit" "$SESSION_FILE")
echo "BEFORE: await noise.finishInit count = $BEFORE_AWAIT (expecting 1)"
if [ "$BEFORE_AWAIT" != "1" ]; then
  echo "FAIL: expected exactly 1 'await noise.finishInit' before patch"
  exit 1
fi
perl -i -pe 's/await noise\.finishInit\(\);/noise.finishInit();/' "$SESSION_FILE"
echo "perl rc=$?"
AFTER_AWAIT=$(grep -c "await noise\.finishInit" "$SESSION_FILE")
AFTER_NOISE=$(grep -c "noise\.finishInit()" "$SESSION_FILE")
echo "AFTER: await noise.finishInit count = $AFTER_AWAIT (expecting 0)"
echo "AFTER: noise.finishInit() count = $AFTER_NOISE (expecting >= 1)"
if [ "$AFTER_AWAIT" != "0" ]; then
  echo "FAIL: await noise.finishInit still present"
  exit 1
fi
if [ "$AFTER_NOISE" -lt "1" ]; then
  echo "FAIL: noise.finishInit() not found after patch"
  exit 1
fi
dump_counts "AFTER patch 4"

echo "=== Final verification ==="
LID_AFTER=$(grep -c 'lidDbMigrated: false' "$SESSION_FILE")
PT_AFTER=$(grep -c 'passive: true' "$SESSION_FILE")
PROXY_AFTER=$(grep -c 'WHATSAPP_PROXY_URL' "$SESSION_FILE")
echo "Final: lid=$LID_AFTER pt=$PT_AFTER proxy=$PROXY_AFTER"

if [ "$LID_AFTER" -gt "0" ] || [ "$PT_AFTER" -gt "0" ] || [ "$PROXY_AFTER" -lt "1" ]; then
  echo "FAIL: verification failed"
  exit 1
fi

echo "=== ALL PATCHES OK ==="
