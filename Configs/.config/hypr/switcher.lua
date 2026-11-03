if rawget(_G, "__switcher") then
  return true
end

local switcher = { holding = false, alt = {}, down = {} }
_G.__switcher = switcher

local function send(name)
  hl.dispatch(hl.dsp.global("switcher:" .. name))
end

local ALT_OPTIONS = {
  { "altwin:alt_win", { [133] = true, [134] = true } },
  { "altwin:swap_ralt_rwin", { [108] = false, [134] = true } },
  { "compose:ralt", { [108] = false } },
  { "ctrl:ralt_rctrl", { [108] = false } },
  { "grp:lalt_toggle", { [64] = false } },
  { "grp:switch", { [108] = false } },
  { "korean:ralt_hangul", { [108] = false } },
  { "korean:ralt_hanja", { [108] = false } },
  { "lv3:ralt_switch", { [108] = false } },
  { "lv3:ralt_switch_multikey", { [108] = false } },
  { "lv5:ralt_switch", { [108] = false } },
  { "lv5:ralt_switch_lock", { [108] = false } },
  { "grp:alt_altgr_toggle", { [64] = true, [108] = false } },
  { "grp:lswitch", { [64] = false } },
  { "lv3:alt_switch", { [64] = false, [108] = false } },
  { "lv3:lalt_switch", { [64] = false } },
  { "altwin:alt_super_win", { [64] = true, [134] = true } },
  { "altwin:ctrl_alt_win", { [37] = false, [64] = false, [105] = false, [108] = false, [133] = true, [134] = true } },
  { "altwin:swap_alt_win", { [64] = false, [108] = false, [133] = true, [134] = true } },
  { "altwin:swap_lalt_lwin", { [64] = false, [133] = true } },
  { "ctrl:lctrl_meta", { [37] = true } },
  { "ctrl:rctrl_ralt", { [105] = true, [108] = false } },
  { "ctrl:swap_lalt_lctl_lwin", { [37] = false, [64] = false, [133] = true } },
  { "ctrl:swap_lalt_lctl", { [37] = true, [64] = false } },
  { "ctrl:swap_ralt_rctl", { [105] = true, [108] = false } },
  { "grp:toggle", { [108] = false } },
}

local MAY_BE_ALT = { [37] = true, [64] = true, [105] = true, [108] = true, [133] = true, [134] = true }

local function setting(key)
  local ok, value = pcall(hl.get_config, key)
  return ok and type(value) == "string" and value or ""
end

local function alt_keycodes()
  local options = "," .. setting("input.kb_options"):gsub("%s", "") .. ","
  local keys = { [64] = true, [108] = true }
  local variant = setting("input.kb_variant")
  if variant:find("intl", 1, true) or variant:find("altgr", 1, true) then
    keys[108] = nil
  end
  for _, option in ipairs(ALT_OPTIONS) do
    if options:find("," .. option[1] .. ",", 1, true) then
      for code, alt in pairs(option[2]) do
        keys[code] = alt or nil
      end
    end
  end
  return keys
end

local function finish(release)
  if not switcher.holding then
    return
  end
  switcher.holding = false
  if hl.get_current_submap() == "switcher" then
    hl.dispatch(hl.dsp.submap("reset"))
  end
  if release then
    send("release")
  end
end

local function chord(name)
  return function()
    if not switcher.holding then
      switcher.holding = true
      switcher.alt = alt_keycodes()
      for code in pairs(switcher.down) do
        switcher.alt[code] = true
      end
    end
    send(name)
    if switcher.submap and hl.get_current_submap() ~= "switcher" then
      hl.dispatch(hl.dsp.submap("switcher"))
    end
  end
end

local function bind_chords(prefix)
  hl.bind("ALT + TAB", chord("next"), { description = prefix .. "Switcher next window", repeating = true })
  hl.bind("ALT + SHIFT + TAB", chord("previous"), { description = prefix .. "Switcher previous window", repeating = true })
end

hl.on("input.keyboard.key", function(keycode, _, state)
  if MAY_BE_ALT[keycode] then
    switcher.down[keycode] = state ~= 0 or nil
  end
  if state == 0 and switcher.holding and switcher.alt[keycode] then
    finish(true)
  end
end)

hl.on("layer.closed", function(layer)
  if layer and layer.namespace == "switcher" then
    finish(false)
  end
end)

bind_chords("[Window Management|Windows] ")

switcher.submap = pcall(hl.define_submap, "switcher", function() bind_chords("[Hidden] ") end)

pcall(hl.layer_rule, {
  name = "switcher",
  match = { namespace = "^switcher$" },
  no_anim = true,
  animation = "none",
  blur = true,
  ignore_alpha = 0.3,
})

return true
