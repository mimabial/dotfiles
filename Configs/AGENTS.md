# Home Directory Guidelines

## Scope and Source of Truth

- This home directory is the live system.
- Active config lives under `~/.config/`, `~/.local/bin/`, `~/.local/lib/`, `~/.local/share/`, and `~/.local/state/`.
- Do not treat `~/dotfiles/` as the source of truth for persisted config changes.
- Cloned repos are not the active config unless explicitly requested. In particular:
  - `~/HyDE/`
  - `~/omarchy/`
- Other repos in `$HOME` are separate projects. Ignore them unless the task explicitly targets them.

## Core Working Rules

- Understand the problem before editing.
- Do not add new code smells. Fix nearby existing ones when you touch the area.
- Prefer existing helpers and shared libraries over one-off logic.
- Keep config and helper scripts fast, efficient, and low in line count.
- Prefer self-documenting names and structure; comments should explain only non-obvious reasoning.
- Do not take screenshots unless they are necessary for the task.
- Do not add comments that do not clarify non-obvious behavior.
- If syntax, flags, config keys, or API details are uncertain, verify them with local help, man pages, or official docs before changing files.
- Verify the changed path before considering the task done.
- Quickshell is the active bar. Waybar is disabled and retained only as legacy/reference config; do not start, restart, or regenerate it unless explicitly requested.
- Keep bar behavior service-manager agnostic. Quickshell QML and helpers must not call `systemctl`; an external supervisor may run `/usr/bin/quickshell` under systemd today or runit later.

## Live Config and Dotfiles Workflow

- For immediate desktop behavior, edit the live file first.
- If the change should persist, use `~/.local/bin/dotfiles-sync` only when the changed path is not already mirrored.
- A path is already mirrored when it or a parent directory is mapped in `dotfiles-sync.conf`; do not run an extra targeted sync for covered paths.
- When working directly in `~/dotfiles/`, keep paths aligned with the live mirror layout:
  - `~/dotfiles/Configs/.config/`
  - `~/dotfiles/Configs/.local/`
  - `~/dotfiles/Configs/hosts/`
  - `~/dotfiles/Scripts/`
- Do not update cloned reference repos to change your actual desktop configuration.

## Key Paths

- `~/.config/hypr/` - Live Hyprland config and user overrides.
- `~/.config/hypr/themes/` - Theme packs and theme assets.
- `~/.config/quickshell/` - Active status bar: QML behavior, data-driven layouts, styles, and popups. Read its `README.md` before editing.
- `~/.local/lib/hypr/` - Shared Hypr shell library; `core/common.sh` is the common foundation.
- `~/.local/lib/hypr/core/` - Core notification, state, system, wallpaper, and rofi helpers.
- `~/.local/bin/` - User-facing entrypoints and wrappers such as `hyprshell`, `dotfiles-sync`, and `auto-theme`.
- `~/.local/state/hypr/` - Runtime Hypr state and exported config.
- `~/.cache/wal/` - Generated pywal colors and derived outputs.
- `~/dotfiles/Configs/` - Mirror of the live config tree.
- `~/dotfiles/Scripts/` - Install, restore, migration, and helper scripts.

## Common Commands

- `hyprshell list` - discover available script entrypoints.
- `eval "$(hyprshell init)"` - load Hypr shell environment for direct script runs.
- `hyprshell theme.switch.sh -s "<Theme Name>"` - switch theme and regenerate colors.
- `hyprshell wallpaper next --global` - rotate wallpaper and regenerate colors.
- `hyprshell quickshell/layout select` - choose a Quickshell layout; `list`, `next`, `previous`, and `set <name>` are also supported.
- `quickshell ipc call bar reload` - force a deterministic Quickshell configuration reload.
- `hyprctl configerrors` - validate Hyprland config.
- `hyprctl reload` - reload Hyprland.
- `~/.local/bin/dotfiles-sync` - sync live changes back into `~/dotfiles/Configs/`.
- `cd ~/dotfiles && ./install.sh -r` - restore repo changes onto the live system.

## Script and Config Conventions

- Bash: use `[[ ... ]]`, quote paths, and prefer explicit fallback handling.
- Use absolute paths for config and state references where practical.
- Keep functions small and composable.
- Avoid backgrounding long work unless the path is already lock-safe.
- For direct Hypr script runs, source `~/.local/lib/hypr/runtime/init.bash` or run `hyprshell init` first.
- Do not edit runtime state like `staterc` directly; use the existing state and lock helpers.
- Quickshell QML: declare what a component uses as `required property <Type> <name>` and bind it at the instantiation site. Reaching a sibling `id` defined in the parent file works only through QML's creation-context leak, is flagged `[unqualified]`, and breaks under `pragma ComponentBehavior: Bound`.
- Hyprland keybinds: letters and submaps only, never punctuation. `resolve_binds_by_sym` resolves against the active layout's level-1 keysym, so punctuation binds are silently dead on the `fr` layout. See CLAUDE.md "Pattern 2: Keybinding Changes".

## Verification Expectations

- Bash changes: run `bash -n` on touched scripts.
- Zsh changes: run `zsh -n` on touched functions and completions.
- Hyprland config changes: run `hyprctl configerrors` before reload.
- Theme pipeline changes: exercise `hyprshell theme.switch.sh -s "<Theme Name>"` or `hyprshell wallpaper next --global` and inspect generated outputs.
- Quickshell QML changes: run `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell -I ~/.cache/qmllint` on touched files — never bare `qmllint`, which is the qt5 build and exits 0 without resolving types — then reload the bar and inspect new log output; validate layout/style JSON with `jq empty`. See CLAUDE.md "Verification Expectations" for the `pragma ComponentBehavior: Bound` and delegate rules.
- Waybar changes: only verify Waybar when explicitly working on or re-enabling the legacy bar.
- Notification changes: prefer dry runs or non-destructive test paths.

## Version Control Guardrails

- Before any destructive VCS operation in a repo, check the repo state first.
- Never discard or overwrite uncommitted user changes without explicit permission.
- Prefer the target repo's existing VCS workflow and tooling; do not assume every repo uses the same commands.
- If a repo has its own guidance, follow it before applying generic habits.

Minimum safe check before rebases, restores, resets, or abandons:

```bash
git status --short
git diff --stat
```

## Restricted Actions

- Never push without explicit user permission.
- Never SSH or run remote-copy commands without explicit user permission.
- Never deploy without explicit user permission.
- When asking for permission, show the exact command you intend to run.

## Home Directory Boundaries

- `~/HyDE/` and `~/omarchy/` are references, not the active config.
- `~/bema-django/`, `~/bema-java/`, `~/bema-next/`, and `~/LyricaV2/` are separate projects.
- If the task is about "my config", start from the live config paths, not the reference repos.
