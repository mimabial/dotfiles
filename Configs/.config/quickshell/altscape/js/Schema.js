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
  var fallbacks = {};
  for (var item of items) fallbacks[item.key] = item.fallback;
  return fallbacks;
}

var itemByKey = (function() {
  var byKey = {};
  for (var item of items) byKey[item.key] = item;
  return byKey;
})();

function clean(key, value) {
  var item = itemByKey[key];
  if (!item) return value;
  if (value === null || value === undefined) return item.fallback;
  switch (item.kind) {
  case "enum":
    return item.options.indexOf(String(value)) >= 0 ? String(value) : item.fallback;
  case "bool":
    if (value === true || value === "true") return true;
    if (value === false || value === "false") return false;
    return item.fallback;
  default:
    return value;
  }
}

function migrate(values) {
  var out = Object.assign({}, values);
  for (var removedKey of removedKeys) delete out[removedKey];
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
