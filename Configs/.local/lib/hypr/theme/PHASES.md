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
theme_apply_run_color_sync         color-sync.sh: pywal16 + colors-shell.sh
theme_apply_commit_theme_metadata  promote staged theme metadata and generate native Lua
theme_apply_display_wallpaper     submit current wall.set to the backend
theme_apply_update_waybar_border_radius
theme_apply_start_envelope         fork phase D in a systemd-run user slice
theme_apply_start_job (3x)         hypr_reload, waybar_css/start, kitty
theme_apply_start_detached_job     dunst, firefox
theme_apply_wait_jobs              block on the 3 phase-A jobs
```

The 3 phase-A jobs are required. Wallpaper display is submitted before the
detached envelope starts, so it does not lag behind phase-D bootstrap.
Waybar is not restarted for theme CSS: generated CSS is hot-reloaded by
Waybar itself, and the job only writes the font include and starts Waybar if
it is missing. Dunst and Firefox are best-effort detached jobs. The main
wait is here; the user sees their desktop restyled once
`theme_apply_wait_jobs` returns.

## Phase D — detached envelope (theme.apply.phase_d.bash)

Runs in `hyprshell-theme-${gen}.service`, scoped to `background.slice`,
with reduced CPU/IO weight. Survives the foreground exiting. Each job
short-circuits via `theme_apply_generation_is_current` if the persisted
generation has moved on, so a newer foreground apply implicitly cancels
the current envelope's remaining work.

Phase-D work is all best-effort. It runs app theming that the user does
not need synchronized to the keypress: gtk, qt, chrome, gimp, theme_files
(alacritty/tmux/rofi), secondary_updates, static_desktop, tmux, rmpc,
nvim, runtime_desktop, backend_wallpaper_links, wallpaper maintenance for
hyprlock/current links, wallpaper_thumbs.

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
the entrypoint top-to-bottom, sources `theme.apply.phase_d.bash`, hits
the `--theme-envelope` dispatch on line 463 of `theme.apply.sh`, and
calls `theme_apply_run_envelope_cli` which:

1. parses the envelope args, sets `theme_apply_generation`
2. calls `theme_apply_phase_d_bootstrap` — sources `color.files.sh` +
   `color.finalize.sh` for the secondary_updates job
3. forks wallpaper resume into the same cgroup
4. runs the 14 phase-D jobs via `theme_apply_phase_d_run_jobs`
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
  re-entry, phase-D bootstrap, the 14 phase-D jobs, phase-D-only helpers
  (sync_nvim_theme, enqueue_wallpaper_thumbs, sync_backend_wallpaper_links,
  sync_runtime_desktop_state, run_static_desktop_sync,
  run_phase_d_script, envelope_launch_wallpaper)
