// proxy-bootstrap.cjs
// Loaded via NODE_OPTIONS=--require so it runs before the gateway starts.
// Exposes HttpsProxyAgent as a global so the patched ESM bundle can use it
// without needing to call require() (which doesn't exist in ESM context).

try {
  const { HttpsProxyAgent } = require('https-proxy-agent');
  globalThis.__HttpsProxyAgent__ = HttpsProxyAgent;
  console.error('[proxy-bootstrap] HttpsProxyAgent loaded into globalThis');
} catch (err) {
  console.error('[proxy-bootstrap] failed to load https-proxy-agent:', err && err.message);
}
