(() => {
  let media = null;
  let mediaListeners = null;
  let bridgePort = null;

  const playlistCapabilities = () =>
    globalThis.fftabPlaylistNavigation?.capabilities(document, location.href) || {
      canGoNext: false,
      canGoPrevious: false,
    };

  const pickMediaElement = (requirePlaying) => {
    const mediaElements = [...document.querySelectorAll("video, audio")];
    if (!mediaElements.length) return null;
    const playing = mediaElements.find((element) => !element.paused && !element.ended);
    if (playing || requirePlaying) return playing || null;
    return mediaElements.sort((a, b) => (b.duration || 0) - (a.duration || 0))[0];
  };

  const currentMediaState = () => {
    if (!media) return null;
    return {
      title: document.title || location.hostname,
      url: location.href,
      site: location.hostname,
      status: media.paused || media.ended ? "Paused" : "Playing",
      position: media.currentTime || 0,
      duration: Number.isFinite(media.duration) ? media.duration : 0,
      rate: media.playbackRate || 1,
      ...playlistCapabilities(),
    };
  };

  const connectBridge = () => {
    bridgePort = browser.runtime.connect({ name: "fftab-media" });
    bridgePort.onMessage.addListener((msg) => {
      if (msg && msg.type === "report") reportMediaState("report");
    });
    bridgePort.onDisconnect.addListener(() => {
      bridgePort = null;
    });
    return bridgePort;
  };

  const reportMediaState = (eventName) => {
    const mediaState = currentMediaState();
    if (!mediaState) return;
    (bridgePort || connectBridge()).postMessage({ type: "update", state: mediaState, event: eventName || "" });
  };

  const attachMediaElement = (element) => {
    if (media === element) return;
    mediaListeners?.abort();
    mediaListeners = new AbortController();
    media = element;
    element.addEventListener(
      "pause",
      () => {
        if (element.isConnected) return;
        releaseMediaElement();
        rescanMediaElements(true);
      },
      { signal: mediaListeners.signal }
    );
    reportMediaState("attach");
  };

  // Firefox only autostarts muted, so muted-on-play means trailer, not track.
  const worthAttaching = (element) => !element.muted;

  const releaseMediaElement = () => {
    mediaListeners?.abort();
    mediaListeners = null;
    media = null;
    bridgePort?.postMessage({ type: "released" });
  };

  const rescanMediaElements = (requirePlaying) => {
    const element = pickMediaElement(requirePlaying);
    // A command means the user asked for this tab, so honour it even when muted.
    if (element && (!requirePlaying || worthAttaching(element))) attachMediaElement(element);
  };

  for (const eventName of ["play", "pause", "seeked", "ratechange", "durationchange", "ended"]) {
    document.addEventListener(
      eventName,
      (event) => {
        if (!(event.target instanceof HTMLMediaElement)) return;
        if (eventName === "play" && worthAttaching(event.target)) attachMediaElement(event.target);
        if (event.target !== media) return;
        if (eventName === "ended" && !pickMediaElement(true)) {
          reportMediaState(eventName);
          releaseMediaElement();
          return;
        }
        reportMediaState(eventName);
      },
      true
    );
  }

  browser.runtime.onMessage.addListener((msg) => {
    if (!msg || msg.type !== "command") return;
    if (!media) rescanMediaElements();
    if (!media) return;
    switch (msg.command) {
      case "play":
        media.play();
        break;
      case "pause":
        media.pause();
        break;
      case "playpause":
        media.paused ? media.play() : media.pause();
        break;
      case "stop":
        media.pause();
        media.currentTime = 0;
        break;
      case "seek":
        media.currentTime = Math.max(0, media.currentTime + (msg.offset || 0));
        break;
      case "setposition":
        media.currentTime = Math.max(0, msg.position || 0);
        break;
      case "next":
      case "previous":
        globalThis.fftabPlaylistNavigation?.navigate(
          msg.command,
          document,
          location.href
        );
        break;
    }
  });

  rescanMediaElements(true);
})();
