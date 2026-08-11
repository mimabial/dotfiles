# Theme apply phases

A theme switch fans work out across two phases. Phase A is everything the
user has to wait on; phase D is everything that can be cancelled by the
next theme switch.

## Phase A — foreground (theme.apply.sh)

Holds the `theme_update` lock end-to-end. Bumps the generation counter
once. Runs in the foreground until the user-visible apps have been updated.

```
theme_apply_next_generation        increment + cancel previous phase-D units
theme_apply_prepare_common_state   acquire theme_update lock
theme_apply_commit_theme_metadata  promote staged theme metadata and generate native Lua
theme_apply_run_color_sync         color-sync.sh: pywal16 + colors-shell.sh
theme_apply_start_job (3x)         wallpaper, waybar (radius/font/icon), kitty
theme_apply_start_detached_job     dunst, firefox
theme_apply_wait_jobs              block on all foreground jobs
theme_apply_start_envelope         fork phase D after wallpaper submission
```

Metadata is committed before the color sync so that `theme.lua` is already on
disk when `hypr-theme` runs its own `hyprctl reload config-only` at the end of
the sync. That single reload picks up both generated Lua files, so phase A no
longer issues a reload of its own — a second reload would drop whatever submap
the user is in.

Waybar and Kitty are required; wallpaper is best-effort. All three run in
parallel, and the detached envelope starts only after wallpaper submission.
Waybar is not restarted for theme CSS: generated CSS is hot-reloaded by
Waybar itself. The waybar job writes the font include and the dconf icon
sink (gsettings), then restarts Waybar only when the icon theme changed —
against the sink it just wrote — or starts it if missing; the phase-D
`waybar_icon_sync` stays as a safety net behind it. Dunst and Firefox are
best-effort detached jobs. The main wait is here; the user sees their
desktop restyled once `theme_apply_wait_jobs` returns.

## Phase D — detached envelope (theme.apply.phase_d.bash)

Runs in `hyprshell-theme-${gen}.service`, scoped to `background.slice`,
with reduced CPU/IO weight. Survives the foreground exiting. Each job
short-circuits via `theme_apply_generation_is_current` if the persisted
generation has moved on, so a newer foreground apply implicitly cancels
the current envelope's remaining work.

Phase-D work is best-effort. Eight jobs run in parallel: `secondary_updates`,
`static_desktop`, `tmux`, `rmpc`, `nvim`, `runtime_desktop`,
`backend_wallpaper_links`, and `wallpaper_thumbs`. The envelope also resumes
wallpaper maintenance and runs `waybar_icon_sync` after the job barrier.
Application files are generated earlier by `hypr-theme`'s renderer scan.

## Cancellation

`theme_apply_next_generation` increments and persists the generation
*before* anything else. It also calls
`theme_apply_cancel_previous_phase_d_jobs` which kills any earlier
envelope unit by stopping the systemd unit and SIGKILLing the cgroup.
Inside an envelope subprocess, every phase-D job calls
`theme_apply_generation_is_current` first; the result is loaded fresh from
state on each call, so a newer foreground bump is observed even from
inside a long-running phase-D job.

The two cancellation mechanisms (systemd kill + per-job generation check)
overlap intentionally — systemd handles the cgroup-wide stop, the
generation check handles the gap before systemd has reaped everything.

## Re-entry: `theme.apply.sh --theme-envelope`

`theme_apply_start_envelope` forks `bash theme.apply.sh --theme-envelope
--generation N --log-dir DIR --unit-file FILE`. That subprocess re-runs
the entrypoint top-to-bottom, sources `theme.apply.phase_d.bash`, and calls
`theme_apply_run_envelope_cli` through the `--theme-envelope` dispatch:

1. parses the envelope args, sets `theme_apply_generation`
2. calls `theme_apply_phase_d_bootstrap` — sources `color.finalize.sh`
   for the secondary_updates job
3. forks wallpaper resume into the same cgroup
4. runs the eight phase-D jobs via `theme_apply_phase_d_run_jobs`
5. prunes old phase-D log directories (keep `HYPR_THEME_PHASE_D_LOG_KEEP`,
   default 20)

## State the phases agree on

- `~/.local/state/hypr/staterc` — `theme_apply_generation` (the source of
  truth for `theme_apply_generation_is_current`)
- `${XDG_RUNTIME_DIR}/hypr/theme.apply.phase-d.units/${gen}-envelope.unit`
  — file naming the systemd unit to cancel
- `~/.cache/hypr/theme.apply.phase-d/${gen}.${pid}/` — per-envelope job
  log directory, written by both phase-D jobs and the wallpaper resume

## What lives where

- `theme.apply.sh` — phase A orchestration, lock + metadata, the 3
  foreground jobs, shared primitives (timing, generation counter, job
  pool, wallpaper display, restart/start helpers, desktop-state prep)
- `lib/theme.apply.phase_d.bash` — envelope start, envelope CLI
  re-entry, phase-D bootstrap, the eight phase-D jobs, phase-D-only helpers
  (sync_nvim_theme, enqueue_wallpaper_thumbs, sync_backend_wallpaper_links,
  sync_runtime_desktop_state, run_static_desktop_sync, envelope_launch_wallpaper)
