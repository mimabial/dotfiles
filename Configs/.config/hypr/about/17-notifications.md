# Notifications

Notifications are [dunst](https://dunst-project.org/), themed by the pipeline,
with an archive behind the bar so nothing you missed is actually gone.

## The archive

Every notification is written to `~/.local/state/hypr/notifications/` as it
arrives — text, metadata and any image it carried. The bar keeps an unread count
and opens the archive as a popup.

From the shell:

```bash
hyprshell notify/archive list [LIMIT]   # newest first, JSON, default 200
hyprshell notify/archive unread         # count since the panel was last opened
hyprshell notify/archive remove KEY
hyprshell notify/archive clear
hyprshell notify/archive prune
```

Retention is configured in `staterc` rather than in dunst:

| key | default |
| --- | ------- |
| `NOTIFY_KEEP_DAYS` | 30 |
| `NOTIFY_MAX_ITEMS` | 1000 |
| `NOTIFY_ARCHIVE_SKIP_APPS` | — |
| `NOTIFY_ARCHIVE_SKIP_TAGS` | — |

The two skip lists are `|`-separated, and they are what you want for the chatty
ones. Volume and brightness notifications fire every time you touch a key; there
is no reason to keep 400 of them.

## dunstrc is generated

This one catches people out. `~/.config/dunst/dunstrc` is written in full by
`render/dunst.py` on every theme apply — palette, layout and rules. Editing it
does nothing that survives your next theme switch.

Edit `~/.config/dunst/dunst.conf` instead. The renderer reads it as the base and
appends the generated block. And dunst does **not** reload on save:

```bash
dunstctl reload
```

## Stack tags

Notifications that would otherwise pile up use a stack tag, so the new one
replaces the old one in place instead of adding a row. That is why holding the
volume key gives you one notification that changes rather than twenty that
stack. If you write a script that notifies repeatedly, give it a tag:

```bash
dunstify -h "string:x-dunst-stack-tag:mytag" "Title" "Body"
```

## GitHub

There is a GitHub notification poller under `notify/` that surfaces mentions and
review requests through the same path, so they land in the archive with
everything else.
