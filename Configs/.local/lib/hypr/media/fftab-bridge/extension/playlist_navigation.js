(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.fftabPlaylistNavigation = api;
  }
})(globalThis, () => {
  const ITEM_SELECTOR = "ytd-playlist-panel-video-renderer";
  const ITEM_LINK_SELECTOR = "a#wc-endpoint, a[href*='/watch']";

  const playlistUrl = (url) => {
    try {
      const parsed = new URL(url);
      const youtube = /(^|\.)youtube\.com$/i.test(parsed.hostname);
      return youtube && parsed.searchParams.has("list") ? parsed : null;
    } catch (_error) {
      return null;
    }
  };

  const usable = (element) =>
    Boolean(
      element &&
        !element.hidden &&
        !element.disabled &&
        element.getAttribute?.("aria-disabled") !== "true" &&
        element.getAttribute?.("aria-hidden") !== "true" &&
        !element.classList?.contains("ytp-disabled")
    );

  const itemLink = (item) => item?.querySelector?.(ITEM_LINK_SELECTOR) || null;

  const selectedItemIndex = (items) =>
    items.findIndex(
      (item) =>
        item.hasAttribute?.("selected") ||
        item.getAttribute?.("aria-current") === "true" ||
        Boolean(item.querySelector?.("[aria-current='true']"))
    );

  const context = (doc, url) => {
    const parsed = playlistUrl(url);
    if (!parsed) return null;
    const items = [...doc.querySelectorAll(ITEM_SELECTOR)];
    return {
      doc,
      items,
      selected: selectedItemIndex(items),
      index: Number.parseInt(parsed.searchParams.get("index") || "", 10),
    };
  };

  const control = (doc, direction) =>
    doc.querySelector(
      direction === "next" ? ".ytp-next-button" : ".ytp-prev-button"
    );

  const targetItem = (playlist, direction) => {
    if (playlist.selected < 0) return null;
    const offset = direction === "next" ? 1 : -1;
    return playlist.items[playlist.selected + offset] || null;
  };

  const capabilities = (doc, url) => {
    const playlist = context(doc, url);
    if (!playlist) return { canGoNext: false, canGoPrevious: false };

    const nextItem = itemLink(targetItem(playlist, "next"));
    const previousItem = itemLink(targetItem(playlist, "previous"));
    return {
      canGoNext: usable(nextItem) || usable(control(doc, "next")),
      canGoPrevious:
        usable(previousItem) ||
        usable(control(doc, "previous")) ||
        (Number.isFinite(playlist.index) && playlist.index > 1),
    };
  };

  const click = (element) => {
    if (!usable(element) || typeof element.click !== "function") return false;
    element.click();
    return true;
  };

  const callPlayer = (doc, direction) => {
    const wrapped = doc.getElementById?.("movie_player");
    const player = wrapped?.wrappedJSObject || wrapped;
    const method = direction === "next" ? "nextVideo" : "previousVideo";
    if (!player || typeof player[method] !== "function") return false;
    player[method]();
    return true;
  };

  const navigate = (direction, doc, url) => {
    if (direction !== "next" && direction !== "previous") return false;
    const playlist = context(doc, url);
    if (!playlist) return false;
    const available = capabilities(doc, url);
    if (direction === "next" && !available.canGoNext) return false;
    if (direction === "previous" && !available.canGoPrevious) return false;

    return (
      click(itemLink(targetItem(playlist, direction))) ||
      click(control(doc, direction)) ||
      callPlayer(doc, direction)
    );
  };

  return { capabilities, navigate };
});
