let port = null;
const seen = new Map(); // tabId -> last update ms

function connect() {
  try {
    port = browser.runtime.connectNative("fftab_bridge");
  } catch (e) {
    port = null;
    setTimeout(connect, 5000);
    return;
  }
  port.onMessage.addListener((msg) => {
    if (msg && msg.type === "command" && seen.has(msg.tabId)) {
      browser.tabs.sendMessage(msg.tabId, msg).catch(() => {});
    }
  });
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, 3000);
  });
}
connect();

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || msg.type !== "update" || !sender.tab || !port) return;
  const tabId = sender.tab.id;
  seen.set(tabId, Date.now());
  port.postMessage({ type: "update", tabId, event: msg.event, ...msg.state });
});

browser.tabs.onRemoved.addListener((tabId) => {
  if (seen.delete(tabId) && port) port.postMessage({ type: "removed", tabId });
});

// Prune tabs that stopped reporting (navigated away, media element gone).
setInterval(() => {
  const now = Date.now();
  for (const [tabId, ts] of seen) {
    if (now - ts > 20000) {
      seen.delete(tabId);
      if (port) port.postMessage({ type: "removed", tabId });
    }
  }
}, 10000);
