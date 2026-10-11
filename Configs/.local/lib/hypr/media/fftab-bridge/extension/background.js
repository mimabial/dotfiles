let nativePort = null;
const mediaPortsByTab = new Map();

function routeHostCommand(msg) {
  if (!msg || msg.type !== "command" || !mediaPortsByTab.has(msg.tabId)) return;
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

function postToNativeHost(message) {
  if (!nativePort) {
    nativePort = browser.runtime.connectNative("fftab_bridge");
    nativePort.onMessage.addListener(routeHostCommand);
    nativePort.onDisconnect.addListener(() => {
      nativePort = null;
    });
    for (const framePorts of mediaPortsByTab.values()) {
      for (const framePort of framePorts.values()) framePort.postMessage({ type: "report" });
    }
  }
  nativePort.postMessage(message);
}

browser.runtime.onConnect.addListener((port) => {
  if (port.name !== "fftab-media" || !port.sender || !port.sender.tab) return;
  const tabId = port.sender.tab.id;
  const frameId = port.sender.frameId;

  const forgetFrame = () => {
    const framePorts = mediaPortsByTab.get(tabId);
    if (!framePorts || !framePorts.delete(frameId) || framePorts.size) return;
    mediaPortsByTab.delete(tabId);
    if (nativePort) nativePort.postMessage({ type: "removed", tabId });
  };

  port.onMessage.addListener((msg) => {
    if (!msg) return;
    if (msg.type === "released") {
      forgetFrame();
      return;
    }
    if (msg.type !== "update") return;
    if (!mediaPortsByTab.has(tabId)) mediaPortsByTab.set(tabId, new Map());
    mediaPortsByTab.get(tabId).set(frameId, port);
    postToNativeHost({ type: "update", tabId, event: msg.event, ...msg.state });
  });
  port.onDisconnect.addListener(forgetFrame);
});
