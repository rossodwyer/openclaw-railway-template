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
replacement = (
    'agent: (function(_url, _explicit) {'
        'try {'
            'var _isWA = /whatsapp\\.(net|com)/i.test(_url || "");'
            'var _proxyUrl = process.env.WHATSAPP_PROXY_URL;'
            'var _decision = _explicit ? "explicit-agent" : (!_proxyUrl ? "no-env-var" : (!_isWA ? "non-whatsapp-url" : (!globalThis.__HttpsProxyAgent__ ? "no-global" : "use-proxy")));'
            'if (globalThis.__fs__) {'
                'globalThis.__fs__.appendFileSync("/tmp/proxy-decision.log", "[" + new Date().toISOString() + "] url=" + _url + " decision=" + _decision + "\\n");'
            '}'
            'if (_explicit) return _explicit;'
            'if (_decision === "use-proxy") return new globalThis.__HttpsProxyAgent__(_proxyUrl);'
            'return undefined;'
        '} catch (_e) {'
            'if (globalThis.__fs__) {'
                'try { globalThis.__fs__.appendFileSync("/tmp/proxy-decision.log", "[" + new Date().toISOString() + "] ERROR: " + (_e && _e.message) + "\\n"); } catch(_){}'
            '}'
            'return _explicit || undefined;'
        '}'
    '})(this.url, this.config.agent)'
)

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
