// proxy-shim.cjs
//
// Loaded via NODE_OPTIONS=--require=/app/proxy-shim.cjs so it runs at process
// startup, before OpenClaw's gateway loads its bundled Baileys. Monkey-patches
// the `ws` package's WebSocket constructor to inject a proxy agent for any
// WebSocket connecting to WhatsApp endpoints.

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
          options = Object.assign({}, protocols, { agent: protocols.agent || agent });
          protocols = undefined;
        } else {
          options = Object.assign({}, options || {}, { agent: (options && options.agent) || agent });
        }
        try {
          require('fs').appendFileSync('/tmp/proxy-shim.log', '[' + new Date().toISOString() + '] injected proxy agent for ' + url + '\n');
        } catch (e) {}
      } else {
        try {
          require('fs').appendFileSync('/tmp/proxy-shim.log', '[' + new Date().toISOString() + '] passthrough (not whatsapp): ' + (url || '<unknown>') + '\n');
        } catch (e) {}
      }

      return new OriginalWebSocket(address, protocols, options);
    }

    Object.setPrototypeOf(PatchedWebSocket, OriginalWebSocket);
    Object.setPrototypeOf(PatchedWebSocket.prototype, OriginalWebSocket.prototype);
    for (const key of Object.keys(OriginalWebSocket)) {
      try { PatchedWebSocket[key] = OriginalWebSocket[key]; } catch (e) {}
    }

    if (ws.WebSocket) {
      ws.WebSocket = PatchedWebSocket;
    }
    require.cache[require.resolve('ws')].exports = PatchedWebSocket;
    PatchedWebSocket.WebSocket = PatchedWebSocket;
    PatchedWebSocket.Server = OriginalWebSocket.Server;
    PatchedWebSocket.WebSocketServer = OriginalWebSocket.WebSocketServer;

    const masked = proxyUrl.replace(/:[^@]*@/, ':***@');
    console.error('[proxy-shim] loaded; will route WhatsApp WebSocket traffic through ' + masked);
  } catch (err) {
    console.error('[proxy-shim] failed to install:', err && err.message);
  }
}
