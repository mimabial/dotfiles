.pragma library

var removedKeys = ["mode","pickOnRelease","showEmpty","tileSize","showTitles","attention","cardStyle","appColors","cornerRadius","effect","closeEffect","selectEffect","speed","backdrop","blurAmount","blurTint","tintStrength","backdropOpacity","middleClick","dim","barDisplay","barText","fontScale","density","opacity","popupOpacity","surfaceTint","frame","colorMode","customBg","customFg","accentColor","previews","iconSize","windowWidth","windowHeight","showCount","windowLayouts"];

var items = [
  { key: "scope", label: "Switch windows from", kind: "enum", fallback: "all", control: "tiles",
    options: ["all", "others", "monitor", "workspace"],
    labels: { all: "All workspaces", others: "Other workspaces", monitor: "This monitor", workspace: "This workspace" },
    hint: "Choose which windows Alt+Tab cycles through. Other workspaces excludes the current workspace." },
  { key: "order", label: "Order", kind: "enum", fallback: "workspace", control: "seg",
    options: ["workspace", "recent"],
    labels: { workspace: "By workspace", recent: "Most recent first" },
    hint: "By workspace visits each workspace’s windows together. Most recent first follows recent focus order." },
  { key: "showSpecial", label: "Scratchpads", kind: "bool", fallback: false,
    hint: "Include windows parked on special workspaces.",
    when: [{ key: "scope", is: ["all", "others", "monitor"] }] }
];

function defaults() {
  var d = {};
  for (var i = 0; i < items.length; i++) d[items[i].key] = items[i].fallback;
  return d;
}

var itemByKey = (function() {
  var m = {};
  for (var i = 0; i < items.length; i++) m[items[i].key] = items[i];
  return m;
})();

function clean(key, v) {
  var it = itemByKey[key];
  if (!it) return v;
  if (v === null || v === undefined) return it.fallback;
  switch (it.kind) {
  case "enum":
    return it.options.indexOf(String(v)) >= 0 ? String(v) : it.fallback;
  case "bool":
    if (v === true || v === "true") return true;
    if (v === false || v === "false") return false;
    return it.fallback;
  default:
    return v;
  }
}

function migrate(values) {
  var out = Object.assign({}, values);
  for (var i = 0; i < removedKeys.length; i++) delete out[removedKeys[i]];
  return out;
}

function applies(conditions, cfg) {
  return !conditions || conditions.every(function(condition) { return condition.is.indexOf(cfg[condition.key]) >= 0; });
}

function resolve(values) {
  var out = {};
  var src = values || {};
  for (var k in itemByKey) out[k] = clean(k, src[k]);
  return out;
}
