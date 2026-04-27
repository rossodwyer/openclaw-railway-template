#!/usr/bin/env python3
"""Inject WHATSAPP_PROXY_URL agent fallback into Baileys WebSocketClient.connect()."""
import sys

if len(sys.argv) != 2:
    print("Usage: proxy-patch.py <session-bundle.js>", file=sys.stderr)
    sys.exit(2)

path = sys.argv[1]
print(f"Opening {path}")

with open(path, 'r') as f:
    content = f.read()
print(f"File length: {len(content)}")

target = 'agent: this.config.agent'
replacement = 'agent: this.config.agent || (process.env.WHATSAPP_PROXY_URL && /whatsapp\\.(net|com)/i.test(this.url) ? new (require("https-proxy-agent").HttpsProxyAgent)(process.env.WHATSAPP_PROXY_URL) : void 0)'

count = content.count(target)
print(f"Target match count: {count}")
if count != 1:
    print(f"FAIL: expected exactly 1 match, got {count}", file=sys.stderr)
    sys.exit(1)

new_content = content.replace(target, replacement, 1)
with open(path, 'w') as f:
    f.write(new_content)
print(f"New file length: {len(new_content)}")
print("Proxy patch applied successfully")
