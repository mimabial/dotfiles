.pragma library

// The option catalogue. Adding a knob is one entry here and nothing else — if a
// change needs edits in both this file and the panel, this file is not carrying
// enough.
//
// Every `key` is validated against the running compositor by SchemaTest in
// ~/.local/lib/hypr/window/tests/test_looknfeel.py. The Hyprland wiki is not the
// contract; the installed build is. `decoration:glow:falloff` and
// `dwindle:pseudotile` are documented upstream but absent here, which is exactly
// what that test catches.
//
// Row shapes:
//   { key, label, type: "int"|"float"|"bool"|"enum", min, max, step, options }
//   { id,  label, type: "float", ... }        synthetic; not queried
//   { id,  label, type: "pipeline", list, set } dispatches to hyprshell

var SECTIONS = [
    {
        title: "Windows",
        rows: [
            { key: "general:gaps_in", label: "Gaps in", type: "int", min: 0, max: 50, step: 1 },
            { key: "general:gaps_out", label: "Gaps out", type: "int", min: 0, max: 50, step: 1 },
            { key: "general:gaps_workspaces", label: "Workspace gaps", type: "int", min: 0, max: 100, step: 1 },
            { key: "general:border_size", label: "Border width", type: "int", min: 0, max: 20, step: 1 },
            { key: "decoration:border_part_of_window", label: "Border inside window", type: "bool" },
            { key: "general:snap:enabled", label: "Snapping", type: "bool" },
            { key: "general:snap:window_gap", label: "Snap window gap", type: "int", min: 0, max: 100, step: 1 },
            { key: "general:snap:monitor_gap", label: "Snap monitor gap", type: "int", min: 0, max: 100, step: 1 }
        ]
    },
    {
        title: "Layout",
        rows: [
            { key: "general:layout", label: "Tiling engine", type: "enum",
              options: ["dwindle", "master", "scrolling"] }
        ]
    },
    {
        title: "Corners",
        rows: [
            { key: "decoration:rounding", label: "Rounding", type: "int", min: 0, max: 50, step: 1 },
            { key: "decoration:rounding_power", label: "Roundness curve", type: "float", min: 1, max: 10, step: 0.1 }
        ]
    },
    {
        title: "Opacity",
        rows: [
            { key: "decoration:active_opacity", label: "Focused", type: "float", min: 0, max: 1, step: 0.01 },
            { key: "decoration:inactive_opacity", label: "Unfocused", type: "float", min: 0, max: 1, step: 0.01 },
            { key: "decoration:fullscreen_opacity", label: "Fullscreen", type: "float", min: 0, max: 1, step: 0.01 }
        ]
    },
    {
        title: "Dimming",
        rows: [
            { key: "decoration:dim_inactive", label: "Dim unfocused", type: "bool" },
            { key: "decoration:dim_strength", label: "Strength", type: "float", min: 0, max: 1, step: 0.01 },
            { key: "decoration:dim_special", label: "Special workspace", type: "float", min: 0, max: 1, step: 0.01 },
            { key: "decoration:dim_around", label: "Dim around", type: "float", min: 0, max: 1, step: 0.01 }
        ]
    },
    {
        title: "Blur",
        rows: [
            { key: "decoration:blur:enabled", label: "Enabled", type: "bool" },
            { key: "decoration:blur:size", label: "Size", type: "int", min: 1, max: 30, step: 1 },
            { key: "decoration:blur:passes", label: "Passes", type: "int", min: 1, max: 10, step: 1 },
            { key: "decoration:blur:noise", label: "Noise", type: "float", min: 0, max: 1, step: 0.001 },
            { key: "decoration:blur:contrast", label: "Contrast", type: "float", min: 0, max: 2, step: 0.01 },
            { key: "decoration:blur:brightness", label: "Brightness", type: "float", min: 0, max: 2, step: 0.01 },
            { key: "decoration:blur:vibrancy", label: "Vibrancy", type: "float", min: 0, max: 1, step: 0.01 },
            { key: "decoration:blur:vibrancy_darkness", label: "Vibrancy darkness", type: "float", min: 0, max: 1, step: 0.01 },
            { key: "decoration:blur:xray", label: "X-ray", type: "bool" },
            { key: "decoration:blur:special", label: "Special workspace", type: "bool" },
            { key: "decoration:blur:popups", label: "Popups", type: "bool" }
        ]
    },
    {
        title: "Shadow",
        rows: [
            { key: "decoration:shadow:enabled", label: "Enabled", type: "bool" },
            { key: "decoration:shadow:range", label: "Range", type: "int", min: 0, max: 100, step: 1 },
            { key: "decoration:shadow:render_power", label: "Falloff", type: "int", min: 1, max: 4, step: 1 },
            { key: "decoration:shadow:scale", label: "Scale", type: "float", min: 0, max: 1, step: 0.01 },
            { key: "decoration:shadow:sharp", label: "Sharp", type: "bool" }
        ]
    },
    {
        title: "Glow",
        rows: [
            { key: "decoration:glow:enabled", label: "Enabled", type: "bool" },
            { key: "decoration:glow:range", label: "Range", type: "int", min: 0, max: 100, step: 1 }
        ]
    },
    {
        title: "Animations",
        rows: [
            { key: "animations:enabled", label: "Enabled", type: "bool" },
            { key: "animations:workspace_wraparound", label: "Wrap workspaces", type: "bool" },
            // Scales the active preset's shipped speeds rather than storing
            // absolute ones, so switching preset stays meaningful.
            { id: "animation_speed", label: "Speed multiplier", type: "float", min: 0.1, max: 5, step: 0.05 }
        ]
    },
    {
        title: "Groups",
        rows: [
            { key: "group:groupbar:enabled", label: "Group bar", type: "bool" },
            { key: "group:groupbar:height", label: "Height", type: "int", min: 1, max: 50, step: 1 },
            { key: "group:groupbar:font_size", label: "Font size", type: "int", min: 1, max: 40, step: 1 },
            { key: "group:groupbar:rounding", label: "Rounding", type: "int", min: 0, max: 20, step: 1 },
            { key: "group:groupbar:indicator_height", label: "Indicator", type: "int", min: 0, max: 20, step: 1 },
            { key: "group:groupbar:gradients", label: "Gradients", type: "bool" },
            { key: "group:groupbar:stacked", label: "Stacked", type: "bool" },
            { key: "group:insert_after_current", label: "Insert after current", type: "bool" },
            { key: "group:merge_groups_on_drag", label: "Merge on drag", type: "bool" }
        ]
    },
    {
        title: "Pipelines",
        rows: [
            { id: "animation_preset", label: "Animation preset", type: "pipeline",
              list: ["window/animations.sh", "--list"], set: ["window/animations.sh", "--set"] },
            { id: "shader", label: "Screen shader", type: "pipeline",
              list: ["window/shaders.sh", "--list"], set: ["window/shaders.sh", "--set"] },
            { id: "workflow", label: "Workflow profile", type: "pipeline",
              list: ["util/workflows.sh", "--list"], set: ["util/workflows.sh", "--set"] }
        ]
    }
]

// Engine knobs are kept out of SECTIONS because only the active engine's rows
// are shown. They are not gated by the compositor — every engine's keys resolve
// whatever `general:layout` is set to — this is purely presentation.
var LAYOUT_ROWS = {
    dwindle: [
        { key: "dwindle:force_split", label: "Force split", type: "int", min: 0, max: 2, step: 1 },
        { key: "dwindle:preserve_split", label: "Preserve split", type: "bool" },
        { key: "dwindle:smart_split", label: "Smart split", type: "bool" },
        { key: "dwindle:default_split_ratio", label: "Default split ratio", type: "float", min: 0.1, max: 1.9, step: 0.01 }
    ],
    master: [
        { key: "master:new_status", label: "New window", type: "enum",
          options: ["master", "slave", "inherit"] },
        { key: "master:new_on_top", label: "New on top", type: "bool" },
        { key: "master:mfact", label: "Master factor", type: "float", min: 0.1, max: 0.9, step: 0.01 },
        { key: "master:orientation", label: "Orientation", type: "enum",
          options: ["left", "right", "top", "bottom", "center"] }
    ],
    scrolling: [
        { key: "scrolling:column_width", label: "Column width", type: "float", min: 0.1, max: 1, step: 0.01 },
        { key: "scrolling:fullscreen_on_one_column", label: "Fullscreen on one column", type: "bool" }
    ]
}

function sections() {
    return SECTIONS
}

function layoutRows(engine) {
    return LAYOUT_ROWS[engine] || []
}

// Only rows backed by a real Hyprland option. Synthetic and pipeline rows carry
// an `id` instead and are driven separately.
function queryKeys() {
    var keys = []
    for (var i = 0; i < SECTIONS.length; i++) {
        var rows = SECTIONS[i].rows
        for (var j = 0; j < rows.length; j++)
            if (rows[j].key) keys.push(rows[j].key)
    }
    return keys
}
