(() => {
  let media = null;

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

  const reportMediaState = (eventName) => {
    const mediaState = currentMediaState();
    if (!mediaState) return;
    browser.runtime
      .sendMessage({ type: "update", state: mediaState, event: eventName || "" })
      .catch(() => {});
  };

  const attachMediaElement = (element) => {
    if (media === element) return;
    media = element;
    reportMediaState("attach");
  };

  // Firefox only autostarts muted, so muted-on-play means trailer, not track.
  const worthAttaching = (element) => !element.muted;

  // Going quiet is the signal; background.js prunes 20s after the last report.
  const releaseMediaElement = () => {
    media = null;
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

  // Heartbeat: keeps positions fresh and lets the background prune dead tabs.
  setInterval(() => {
    if (!media) return;
    if (!media.isConnected) {
      releaseMediaElement();
      rescanMediaElements(true);
      return;
    }
    reportMediaState("tick");
  }, 5000);

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
