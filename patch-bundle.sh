#!/bin/bash
# DO NOT use `set -e` — we want to see all output even on partial failure
set -x

echo "=== patch-bundle.sh START ==="
echo "PWD: $(pwd)"
echo "Whoami: $(whoami)"
echo "Python3: $(which python3) $(python3 --version 2>&1)"
echo "Perl: $(which perl) $(perl --version | head -2)"

SESSION_FILE=$(find /usr/local/lib/node_modules/openclaw/dist -maxdepth 1 -name "session-*.js" | head -1)
echo "SESSION_FILE: $SESSION_FILE"
if [ -z "$SESSION_FILE" ]; then
  echo "ERROR: session-*.js not found in openclaw/dist"
  ls -la /usr/local/lib/node_modules/openclaw/dist/ | head -20
  exit 1
fi
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
perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)passive:\s*true,/\1passive: false,/' "$SESSION_FILE"
PERL1_RC=$?
echo "perl rc=$PERL1_RC"
dump_counts "AFTER patch 1"

echo "=== Patch 2: lidDbMigrated ==="
perl -i -0pe 's/(\bgenerateLoginNode\b[\s\S]*?)\s*lidDbMigrated:\s*false,?\n?//' "$SESSION_FILE"
PERL2_RC=$?
echo "perl rc=$PERL2_RC"
dump_counts "AFTER patch 2"

echo "=== Patch 3: proxy injection ==="
python3 <<PYEOF
import sys
path = "$SESSION_FILE"
print(f"python opening {path}")
with open(path, 'r') as f:
    content = f.read()
print(f"file length: {len(content)}")

target = 'agent: this.config.agent'
replacement = 'agent: this.config.agent || (process.env.WHATSAPP_PROXY_URL && /whatsapp\\\\.(net|com)/i.test(this.url) ? new (require("https-proxy-agent").HttpsProxyAgent)(process.env.WHATSAPP_PROXY_URL) : void 0)'

count = content.count(target)
print(f"target match count: {count}")
if count != 1:
    print(f"FAIL: expected 1 match, got {count}")
    sys.exit(1)

new_content = content.replace(target, replacement, 1)
with open(path, 'w') as f:
    f.write(new_conten
