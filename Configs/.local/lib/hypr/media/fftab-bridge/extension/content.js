(() => {
  let media = null;

  const pick = () => {
    const els = [...document.querySelectorAll("video, audio")];
    if (!els.length) return null;
    return (
      els.find((el) => !el.paused && !el.ended) ||
      els.sort((a, b) => (b.duration || 0) - (a.duration || 0))[0]
    );
  };

  const state = () => {
    if (!media) return null;
    return {
      title: document.title || location.hostname,
      url: location.href,
      site: location.hostname,
      status: media.paused || media.ended ? "Paused" : "Playing",
      position: media.currentTime || 0,
      duration: Number.isFinite(media.duration) ? media.duration : 0,
      rate: media.playbackRate || 1,
    };
  };

  const report = (evt) => {
    const s = state();
    if (!s) return;
    browser.runtime
      .sendMessage({ type: "update", state: s, event: evt || "" })
      .catch(() => {});
  };

  const attach = (el) => {
    if (media === el) return;
    media = el;
    report("attach");
  };

  const rescan = () => {
    const el = pick();
    if (el) attach(el);
  };

  for (const evt of ["play", "pause", "seeked", "ratechange", "durationchange", "ended"]) {
    document.addEventListener(
      evt,
      (e) => {
        if (!(e.target instanceof HTMLMediaElement)) return;
        if (evt === "play") attach(e.target);
        if (e.target === media) report(evt);
      },
      true
    );
  }

  // Heartbeat: keeps positions fresh and lets the background prune dead tabs.
  setInterval(() => {
    if (media) report("tick");
  }, 5000);

  browser.runtime.onMessage.addListener((msg) => {
    if (!msg || msg.type !== "command") return;
    if (!media) rescan();
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
    }
    setTimeout(() => report("command"), 100);
  });

  rescan();
})();
