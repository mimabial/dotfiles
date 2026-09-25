let nativePort = null;
const lastUpdateByTab = new Map();

function connectNativeHost() {
  try {
    nativePort = browser.runtime.connectNative("fftab_bridge");
  } catch (e) {
    nativePort = null;
    setTimeout(connectNativeHost, 5000);
    return;
  }
  nativePort.onMessage.addListener((msg) => {
    if (msg && msg.type === "command" && lastUpdateByTab.has(msg.tabId)) {
      if (msg.command === "raise") {
        browser.tabs
          .get(msg.tabId)
          .then((tab) =>
            Promise.all([
              browser.tabs.update(msg.tabId, { active: true }),
              browser.windows.update(tab.windowId, { focused: true }),
            ])
          )
          .catch(() => {});
        return;
      }
      browser.tabs.sendMessage(msg.tabId, msg).catch(() => {});
    }
  });
  nativePort.onDisconnect.addListener(() => {
    nativePort = null;
    setTimeout(connectNativeHost, 3000);
  });
}
connectNativeHost();

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || msg.type !== "update" || !sender.tab || !nativePort) return;
  const tabId = sender.tab.id;
  lastUpdateByTab.set(tabId, Date.now());
  nativePort.postMessage({ type: "update", tabId, event: msg.event, ...msg.state });
});

browser.tabs.onRemoved.addListener((tabId) => {
  if (lastUpdateByTab.delete(tabId) && nativePort) nativePort.postMessage({ type: "removed", tabId });
});

// Prune tabs that stopped reporting (navigated away, media element gone).
setInterval(() => {
  const now = Date.now();
  for (const [tabId, lastUpdate] of lastUpdateByTab) {
    if (now - lastUpdate > 20000) {
      lastUpdateByTab.delete(tabId);
      if (nativePort) nativePort.postMessage({ type: "removed", tabId });
    }
  }
}, 10000);
