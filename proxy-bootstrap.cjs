// proxy-bootstrap.cjs
// Loaded via NODE_OPTIONS=--require so it runs before the gateway starts.
// Exposes HttpsProxyAgent and fs as globals so the patched ESM bundle can
// use them without needing to call require() (which doesn't exist in ESM).

try {
  const { HttpsProxyAgent } = require('https-proxy-agent');
  globalThis.__HttpsProxyAgent__ = HttpsProxyAgent;
  console.error('[proxy-bootstrap] HttpsProxyAgent loaded into globalThis');
} catch (err) {
  console.error('[proxy-bootstrap] failed to load https-proxy-agent:', err && err.message);
}

try {
  globalThis.__fs__ = require('fs');
  console.error('[proxy-bootstrap] fs loaded into globalThis');
} catch (err) {
  console.error('[proxy-bootstrap] failed to load fs:', err && err.message);
}
