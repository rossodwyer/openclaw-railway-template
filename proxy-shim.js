// proxy-shim.js
//
// Loaded via NODE_OPTIONS=--require=/app/proxy-shim.js so it runs at process
// startup, before OpenClaw's gateway loads its bundled Baileys. Monkey-patches
// the `ws` package's WebSocket constructor to inject a proxy agent for any
// WebSocket connecting to WhatsApp endpoints.
//
// This is necessary because OpenClaw bundles Baileys into dist/session-*.js
// at build time, so we can't pass options through Baileys' makeWASocket
// config without rebuilding OpenClaw from source. Monkey-patching the
// underlying transport library catches every WebSocket regardless of who
// constructed it.
//
// Only patches when WHATSAPP_PROXY_URL is set, and only proxies WebSockets
// to WhatsApp domains so we don't burn proxy bandwidth on unrelated traffic.

const proxyUrl = process.env.WHATSAPP_PROXY_URL;

if (!proxyUrl) {
  console.error('[proxy-shim] WHATSAPP_PROXY_URL not set, skipping');
} else {
  try {
    const ws = require('ws');
    const { HttpsProxyAgent } = require('https-proxy-agent');

    const OriginalWebSocket = ws.WebSocket || ws;
    const agent = new HttpsProxyAgent(proxyUrl);

    function PatchedWebSocket(address, protocols, options) {
      const url = typeof address === 'string' ? address : (address && address.toString && address.toString());
      const isWhatsApp = url && /whatsapp\.(net|com)/i.test(url);

      if (isWhatsApp) {
        if (typeof protocols === 'object' && !Array.isArray(protocols) && protocols !== null) {
          // protocols is actually options
          options = { ...protocols, agent: protocols.agent || agent };
          protocols = undefined;
        } else {
          options = { ...(options || {}), agent: (options && options.agent) || agent };
        }
        try {
          require('fs').appendFileSync('/tmp/proxy-shim.log',
            `[${new Date().toISOString()}] injected proxy agent for ${url}\n`);
        } catch {}
      } else {
        try {
          require('fs').appendFileSync('/tmp/proxy-shim.log',
            `[${new Date().toISOString()}] passthrough (not whatsapp): ${url}\n`);
        } catch {}
      }

      return new OriginalWebSocket(a
