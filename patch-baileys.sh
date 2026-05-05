#!/usr/bin/env bash
set -euo pipefail

# Locate the Baileys installation (might be under @openclaw/whatsapp's deps or top-level)
BAILEYS_PATHS=(
  "/usr/local/lib/node_modules/@openclaw/whatsapp/node_modules/@whiskeysockets/baileys"
  "/usr/local/lib/node_modules/@whiskeysockets/baileys"
)

BAILEYS=""
for path in "${BAILEYS_PATHS[@]}"; do
  if [ -d "$path" ]; then
    BAILEYS="$path"
    break
  fi
done

if [ -z "$BAILEYS" ]; then
  echo "FAIL: Baileys not found in any expected location"
  exit 1
fi

echo "Baileys location: $BAILEYS"
echo "Baileys version: $(grep '"version"' $BAILEYS/package.json)"

VC=$BAILEYS/lib/Utils/validate-connection.js
SOCKET=$BAILEYS/lib/Socket/socket.js

# === BEFORE counts ===
echo "=== BEFORE ==="
echo "passive: true: $(grep -c 'passive: true' $VC)"
echo "lidDbMigrated: false: $(grep -c 'lidDbMigrated: false' $VC)"
echo "await noise.finishInit: $(grep -c 'await noise\.finishInit' $SOCKET)"

# === Patch 1: passive ===
perl -i -pe 's/passive: true,$/passive: false,/' $VC

# === Patch 2: lidDbMigrated ===
perl -i -ne 'print unless /^\s*lidDbMigrated:\s*false\s*,?\s*$/' $VC

# === Patch 4: noise.finishInit await removal ===
perl -i -pe 's/await noise\.finishInit\(\);/noise.finishInit();/' $SOCKET

# === AFTER counts and verification ===
echo "=== AFTER ==="
PT=$(grep -c 'passive: true' $VC)
LID=$(grep -c 'lidDbMigrated: false' $VC)
AWAIT=$(grep -c 'await noise\.finishInit' $SOCKET)
NOISE=$(grep -c 'noise\.finishInit()' $SOCKET)

echo "passive: true: $PT (expecting 0)"
echo "lidDbMigrated: false: $LID (expecting 0)"
echo "await noise.finishInit: $AWAIT (expecting 0)"
echo "noise.finishInit(): $NOISE (expecting >= 1)"

# Validate each step
[ "$PT" -eq 0 ] || { echo "FAIL: passive patch did not apply"; exit 1; }
[ "$LID" -eq 0 ] || { echo "FAIL: lidDbMigrated patch did not apply"; exit 1; }
[ "$AWAIT" -eq 0 ] || { echo "FAIL: await noise.finishInit patch did not apply"; exit 1; }
[ "$NOISE" -ge 1 ] || { echo "FAIL: noise.finishInit() not preserved"; exit 1; }

# Syntax validate
node --check $VC || { echo "FAIL: validate-connection.js parse error"; exit 1; }
node --check $SOCKET || { echo "FAIL: socket.js parse error"; exit 1; }

echo "=== ALL PATCHES OK ==="
