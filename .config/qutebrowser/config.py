# Qutebrowser configuration focused on security and privacy
# with Everforest colorscheme
# Place this file at: ~/.config/qutebrowser/config.py

import os

# Type hints to avoid LSP errors in Neovim
# These are injected by qutebrowser at runtime
try:
    # Runtime: these variables exist
    config = config  # type: ignore  # noqa: F821
    c = c  # type: ignore  # noqa: F821
except NameError:
    # Development: import stubs for better autocomplete
    # This code never runs in qutebrowser
    from config_stub import c, config

# Load the autoconfig (set to False if you only want this config)
config.load_autoconfig(False)

# ==================== EVERFOREST COLOR SCHEME ====================
# Everforest is a green-based, warm color scheme inspired by forests

# Color palette definition
everforest = {
    # Dark background colors
    "bg0": "#2b3339",  # Main background
    "bg1": "#323c41",  # Lighter background
    "bg2": "#3a454a",  # Even lighter background
    "bg3": "#445055",  # Borders and inactive elements
    "bg4": "#4c555b",  # Comments and subtle elements
    "bg5": "#53605c",  # Line numbers, fold column
    # Foreground colors
    "fg": "#d3c6aa",  # Main foreground
    "red": "#e67e80",  # Errors, important alerts
    "orange": "#e69875",  # Warnings
    "yellow": "#dbbc7f",  # Attention, highlights
    "green": "#a7c080",  # Success, additions
    "aqua": "#83c092",  # Links, special
    "blue": "#7fbbb3",  # Info, directories
    "purple": "#d699b6",  # Special keywords
    "grey0": "#7a8478",  # Comments
    "grey1": "#859289",  # Darker comments
    "grey2": "#9da9a0",  # Selection background
}

# ==================== PRIVACY & SECURITY SETTINGS ====================

# User agent - Use a common one to blend in
# This makes your browser fingerprint less unique
c.content.headers.user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Accept language header - Set to English to reduce fingerprinting
c.content.headers.accept_language = "en-US,en;q=0.9"

# Do Not Track header - Request websites not to track you
# Note: This is not legally binding but signals your preference
c.content.headers.do_not_track = True

# Referer header - Control what information is sent about previous page
# 'same-domain' only sends referer to same domain (more private)
c.content.headers.referer = "same-domain"

# Canvas fingerprinting protection - Makes canvas fingerprinting harder
c.content.canvas_reading = False

# WebGL - Disable to prevent fingerprinting (may break some sites)
c.content.webgl = False

# Cookies - Accept no third party cookies for privacy
# Options: 'all', 'no-3rdparty', 'no-unknown-3rdparty', 'never'
c.content.cookies.accept = "no-3rdparty"

# Store cookies only until browser closes (session cookies only)
c.content.cookies.store = False

# DNS prefetching - Disable to prevent DNS leaks
c.content.dns_prefetch = False

# Geolocation - Always ask before sharing location
c.content.geolocation = "ask"

# Microphone and camera access - Always ask
c.content.media.audio_capture = "ask"
c.content.media.video_capture = "ask"
c.content.media.audio_video_capture = "ask"

# Desktop capture (screen sharing) - Always ask
c.content.desktop_capture = "ask"

# Mouse lock (pointer lock) - Always ask
c.content.mouse_lock = "ask"

# Notifications - Ask before showing notifications
c.content.notifications.enabled = "ask"

# ==================== POPUP AND MODAL HANDLING ====================

# Allow JavaScript to open new tabs/windows (popups)
# Set to False for maximum security, True for functionality
c.content.javascript.can_open_tabs_automatically = False

# Allow JavaScript modal dialogs (alert, confirm, prompt)
c.content.javascript.modal_dialog = True

# Allow JavaScript to access clipboard (some sites need this)
# Options: 'none', 'access', 'access-paste'
c.content.javascript.clipboard = "none"

# Site-specific permissions (add sites that need popups)
# config.set('content.javascript.can_open_tabs_automatically', True, '*://example.com/*')

# ==================== SITE-SPECIFIC OVERRIDES ====================

# Example: Allow everything for trusted sites
# for site in ['*://github.com/*', '*://stackoverflow.com/*']:
#     config.set('content.javascript.enabled', True, site)
#     config.set('content.javascript.can_open_tabs_automatically', True, site)

# Disable JavaScript by default (maximum security, will break many sites)
# Uncomment if you want this level of security
# c.content.javascript.enabled = False

# WebRTC IP leak prevention - Disable WebRTC
c.content.webrtc_ip_handling_policy = "disable-non-proxied-udp"

# Autoplay - Disable video/audio autoplay
c.content.autoplay = False

# Plugins (Flash, etc.) - Disable for security
c.content.plugins = False

# PDF.js - Use built-in PDF viewer for security
c.content.pdfjs = True

# SSL/TLS strict mode - Reject any invalid certificates
c.content.tls.certificate_errors = "block"

# Disable reading from local file system
c.content.local_content_can_access_remote_urls = False
c.content.local_content_can_access_file_urls = False

# Private browsing mode - Don't store history
# Uncomment to always use private browsing
# c.content.private_browsing = True

# ==================== ADBLOCKING ====================

# Enable built-in adblocking
c.content.blocking.enabled = True

# Adblock lists including uBlock Origin's default lists
c.content.blocking.adblock.lists = [
    # uBlock Origin default lists
    "https://ublockorigin.pages.dev/filters/filters.txt",
    "https://ublockorigin.pages.dev/filters/badware.txt",
    "https://ublockorigin.pages.dev/filters/privacy.txt",
    "https://ublockorigin.pages.dev/filters/resource-abuse.txt",
    "https://ublockorigin.pages.dev/filters/unbreak.txt",
    "https://ublockorigin.pages.dev/filters/quick-fixes.txt",
    # EasyList (also used by uBlock)
    "https://easylist.to/easylist/easylist.txt",
    "https://easylist.to/easylist/easyprivacy.txt",
    # "https://easylist-downloads.adblockplus.org/easylist-cookie.txt",
    # Additional protection lists
    "https://secure.fanboy.co.nz/fanboy-annoyance.txt",
    "https://secure.fanboy.co.nz/fanboy-social.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2021.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2022.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2023.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2024.txt",
    # Malware protection
    "https://malware-filter.gitlab.io/malware-filter/phishing-filter-hosts.txt",
    "https://someonewhocares.org/hosts/zero/hosts",
    # Regional lists
    "https://easylist-downloads.adblockplus.org/liste_fr.txt",  # France
    # Legacy filters (older but still relevant)
    "https://github.com/uBlockOrigin/uAssets/raw/master/filters/legacy.txt",
    # Cookie consent banners and annoyances
    "https://github.com/uBlockOrigin/uAssets/raw/master/filters/annoyances.txt",
    "https://github.com/uBlockOrigin/uAssets/raw/master/filters/annoyances-cookies.txt",
    "https://github.com/uBlockOrigin/uAssets/raw/master/filters/annoyances-others.txt",
    # 2020 filters (if you want complete historical coverage)
    "https://github.com/uBlockOrigin/uAssets/raw/master/filters/filters-2020.txt",
]

# Use both methods for maximum effectiveness
# 'auto' uses python-adblock if available, falls back to built-in
c.content.blocking.method = "auto"

# Host blocking for additional protection
c.content.blocking.hosts.lists = [
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
    "https://someonewhocares.org/hosts/zero/hosts",
]

# Whitelist (add sites that break with blocking)
# c.content.blocking.whitelist = ['*.example.com']

# ==================== DOWNLOADS ====================

# Ask where to save downloads
c.downloads.location.prompt = True

# Don't open downloads automatically
c.downloads.open_dispatcher = None

# ==================== TABS ====================

# Don't lazy load tabs (more secure, uses more memory)
c.session.lazy_restore = False

# Open new tabs in background
c.tabs.background = True

# ==================== PRIVACY-FOCUSED SEARCH ENGINE ====================

# Set DuckDuckGo as default search engine (privacy-focused)
c.url.searchengines = {
    "DEFAULT": "https://duckduckgo.com/?q={}",
    "ddg": "https://duckduckgo.com/?q={}",
    "g": "https://www.google.com/search?q={}",  # Google as backup
    "sp": "https://www.startpage.com/sp/search?query={}",  # StartPage
    "qw": "https://www.qwant.com/?q={}",  # Qwant
    "aw": "https://wiki.archlinux.org/?search={}",
    "apkg": "https://archlinux.org/packages/?sort=&q={}&maintainer=&flagged=",
    "gh": "https://github.com/search?o=desc&q={}&s=stars",
    "yt": "https://yewtu.be/search?q={}",
}

c.completion.open_categories = [
    "searchengines",
    "quickmarks",
    "bookmarks",
    "history",
    "filesystem",
]

c.url.default_page = "about:blank"
c.url.start_pages = ["about:blank"]

# ==================== DARK MODE FOR WEBSITES ====================

# Qt WebEngine Dark Mode (Recommended - works on most sites)
c.colors.webpage.preferred_color_scheme = "dark"

# Background color for webpages (while loading)
c.colors.webpage.bg = everforest["bg0"]

# Force dark backgrounds in input fields
c.colors.webpage.darkmode.enabled = True
c.colors.webpage.darkmode.algorithm = "lightness-cielab"
c.colors.webpage.darkmode.contrast = 0.0
c.colors.webpage.darkmode.policy.images = "smart"
c.colors.webpage.darkmode.policy.page = "smart"
c.colors.webpage.darkmode.threshold.foreground = 150
c.colors.webpage.darkmode.threshold.background = 205

# ==================== APPEARANCE WITH EVERFOREST THEME ====================

# Completion widget colors
c.colors.completion.category.bg = everforest["bg1"]
c.colors.completion.category.border.bottom = everforest["bg2"]
c.colors.completion.category.border.top = everforest["bg2"]
c.colors.completion.category.fg = everforest["green"]
c.colors.completion.even.bg = everforest["bg0"]
c.colors.completion.odd.bg = everforest["bg1"]
c.colors.completion.fg = everforest["fg"]
c.colors.completion.item.selected.bg = everforest["bg3"]
c.colors.completion.item.selected.border.bottom = everforest["bg3"]
c.colors.completion.item.selected.border.top = everforest["bg3"]
c.colors.completion.item.selected.fg = everforest["fg"]
c.colors.completion.item.selected.match.fg = everforest["yellow"]
c.colors.completion.match.fg = everforest["yellow"]
c.colors.completion.scrollbar.bg = everforest["bg0"]
c.colors.completion.scrollbar.fg = everforest["bg4"]

# Context menu colors
c.colors.contextmenu.disabled.bg = everforest["bg1"]
c.colors.contextmenu.disabled.fg = everforest["grey0"]
c.colors.contextmenu.menu.bg = everforest["bg0"]
c.colors.contextmenu.menu.fg = everforest["fg"]
c.colors.contextmenu.selected.bg = everforest["bg3"]
c.colors.contextmenu.selected.fg = everforest["fg"]

# Download bar colors
c.colors.downloads.bar.bg = everforest["bg0"]
c.colors.downloads.error.bg = everforest["red"]
c.colors.downloads.error.fg = everforest["bg0"]
c.colors.downloads.start.bg = everforest["blue"]
c.colors.downloads.start.fg = everforest["bg0"]
c.colors.downloads.stop.bg = everforest["green"]
c.colors.downloads.stop.fg = everforest["bg0"]

# Hints colors
c.colors.hints.bg = everforest["yellow"]
c.colors.hints.fg = everforest["bg0"]
c.colors.hints.match.fg = everforest["red"]

# Keyhint colors
c.colors.keyhint.bg = everforest["bg0"]
c.colors.keyhint.fg = everforest["fg"]
c.colors.keyhint.suffix.fg = everforest["yellow"]

# Messages colors
c.colors.messages.error.bg = everforest["red"]
c.colors.messages.error.border = everforest["red"]
c.colors.messages.error.fg = everforest["bg0"]
c.colors.messages.info.bg = everforest["bg0"]
c.colors.messages.info.border = everforest["bg2"]
c.colors.messages.info.fg = everforest["fg"]
c.colors.messages.warning.bg = everforest["orange"]
c.colors.messages.warning.border = everforest["orange"]
c.colors.messages.warning.fg = everforest["bg0"]

# Prompts colors
c.colors.prompts.bg = everforest["bg0"]
c.colors.prompts.border = everforest["bg3"]
c.colors.prompts.fg = everforest["fg"]
c.colors.prompts.selected.bg = everforest["bg3"]
c.colors.prompts.selected.fg = everforest["fg"]

# Statusbar colors
c.colors.statusbar.normal.bg = everforest["bg0"]
c.colors.statusbar.normal.fg = everforest["fg"]
c.colors.statusbar.insert.bg = everforest["green"]
c.colors.statusbar.insert.fg = everforest["bg0"]
c.colors.statusbar.passthrough.bg = everforest["blue"]
c.colors.statusbar.passthrough.fg = everforest["bg0"]
c.colors.statusbar.command.bg = everforest["bg0"]
c.colors.statusbar.command.fg = everforest["fg"]
c.colors.statusbar.command.private.bg = everforest["purple"]
c.colors.statusbar.command.private.fg = everforest["bg0"]
c.colors.statusbar.caret.bg = everforest["purple"]
c.colors.statusbar.caret.fg = everforest["bg0"]
c.colors.statusbar.caret.selection.bg = everforest["purple"]
c.colors.statusbar.caret.selection.fg = everforest["bg0"]
c.colors.statusbar.progress.bg = everforest["green"]
c.colors.statusbar.url.fg = everforest["fg"]
c.colors.statusbar.url.hover.fg = everforest["aqua"]
c.colors.statusbar.url.success.http.fg = everforest["green"]
c.colors.statusbar.url.success.https.fg = everforest["green"]
c.colors.statusbar.url.warn.fg = everforest["orange"]
c.colors.statusbar.url.error.fg = everforest["red"]

# Tab bar colors
c.colors.tabs.bar.bg = everforest["bg0"]
c.colors.tabs.even.bg = everforest["bg0"]
c.colors.tabs.even.fg = everforest["fg"]
c.colors.tabs.odd.bg = everforest["bg0"]
c.colors.tabs.odd.fg = everforest["fg"]
c.colors.tabs.selected.even.bg = everforest["bg3"]
c.colors.tabs.selected.even.fg = everforest["fg"]
c.colors.tabs.selected.odd.bg = everforest["bg3"]
c.colors.tabs.selected.odd.fg = everforest["fg"]
c.colors.tabs.pinned.even.bg = everforest["bg2"]
c.colors.tabs.pinned.even.fg = everforest["fg"]
c.colors.tabs.pinned.odd.bg = everforest["bg2"]
c.colors.tabs.pinned.odd.fg = everforest["fg"]
c.colors.tabs.pinned.selected.even.bg = everforest["bg3"]
c.colors.tabs.pinned.selected.even.fg = everforest["fg"]
c.colors.tabs.pinned.selected.odd.bg = everforest["bg3"]
c.colors.tabs.pinned.selected.odd.fg = everforest["fg"]
c.colors.tabs.indicator.start = everforest["green"]
c.colors.tabs.indicator.stop = everforest["green"]
c.colors.tabs.indicator.error = everforest["red"]

# ==================== FONTS & TYPOGRAPHY ====================

# Use a modern font stack with better readability
c.fonts.default_family = [
    "JetBrains Mono",
    "Fira Code",
    "Cascadia Code",
    "DejaVu Sans Mono",
    "monospace",
]
c.fonts.default_size = "14pt"

# Specific font sizes for UI elements
c.fonts.completion.category = "bold 13pt default_family"
c.fonts.completion.entry = "11pt default_family"
c.fonts.statusbar = "11pt default_family"
c.fonts.tabs.selected = "bold 11pt default_family"
c.fonts.tabs.unselected = "11pt default_family"
c.fonts.hints = "bold 10pt default_family"
c.fonts.messages.info = "11pt default_family"
c.fonts.messages.error = "bold 11pt default_family"

# Web fonts - allow for better looking websites
c.fonts.web.family.standard = "Inter"
c.fonts.web.family.serif = "Georgia"
c.fonts.web.family.sans_serif = "Inter"

# ==================== UI STYLING & VISUAL IMPROVEMENTS ====================

# Tab bar styling
c.tabs.position = "top"
c.tabs.width = "15%"
c.tabs.min_width = 150
c.tabs.max_width = 300
c.tabs.padding = {"bottom": 8, "left": 8, "right": 8, "top": 8}
c.tabs.favicons.scale = 1.2
c.tabs.indicator.width = 3
c.tabs.title.format = "{audio}{index}: {current_title}"
c.tabs.title.format_pinned = "{audio}{index}"

# Status bar styling
c.statusbar.padding = {"bottom": 5, "left": 5, "right": 5, "top": 5}
c.statusbar.widgets = ["keypress", "url", "scroll", "history", "tabs", "progress"]

# Completion menu styling
c.completion.height = "40%"
c.completion.scrollbar.width = 12
c.completion.scrollbar.padding = 2

# Prompt styling
c.prompt.radius = 8

# Message styling
c.messages.timeout = 4000

# Apply Qt stylesheet for custom look
c.qt.args = ["enable-gpu-rasterization", "enable-features=WebContentsForceDark"]

# ==================== ENHANCED COLOR SCHEME WITH GRADIENTS ====================

# Gradient color effects for specific elements
c.colors.statusbar.normal.bg = everforest["bg0"]
c.colors.statusbar.normal.fg = everforest["fg"]
c.colors.statusbar.private.bg = (
    "qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 "
    + everforest["purple"]
    + ", stop:1 "
    + everforest["blue"]
    + ")"
)
c.colors.statusbar.private.fg = everforest["bg0"]
c.colors.statusbar.insert.bg = (
    "qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 "
    + everforest["green"]
    + ", stop:1 "
    + everforest["aqua"]
    + ")"
)
c.colors.statusbar.insert.fg = everforest["bg0"]

# Tab colors with better contrast
c.colors.tabs.bar.bg = everforest["bg0"]
c.colors.tabs.even.bg = everforest["bg1"]
c.colors.tabs.even.fg = everforest["fg"]
c.colors.tabs.odd.bg = everforest["bg1"]
c.colors.tabs.odd.fg = everforest["fg"]
c.colors.tabs.selected.even.fg = everforest["yellow"]
c.colors.tabs.selected.odd.fg = everforest["yellow"]

# Pinned tabs with special styling
c.colors.tabs.pinned.even.bg = everforest["bg2"]
c.colors.tabs.pinned.even.fg = everforest["orange"]
c.colors.tabs.pinned.odd.bg = everforest["bg2"]
c.colors.tabs.pinned.odd.fg = everforest["orange"]
c.colors.tabs.pinned.selected.even.bg = everforest["orange"]
c.colors.tabs.pinned.selected.even.fg = everforest["bg0"]
c.colors.tabs.pinned.selected.odd.bg = everforest["orange"]
c.colors.tabs.pinned.selected.odd.fg = everforest["bg0"]

# Better hint styling
c.hints.border = "2px solid " + everforest["yellow"]
c.hints.radius = 4

# ==================== SCROLLBAR STYLING ====================

c.scrolling.bar = "overlay"  # Modern overlay scrollbars
c.scrolling.smooth = True

# ==================== WINDOW TRANSPARENCY (for Hyprland) ====================

# Make qutebrowser slightly transparent (requires compositor)
# This is handled by Hyprland rules, but we can request it
c.window.transparent = False  # Set to True if you want transparency

# ==================== MISCELLANEOUS ====================

# Enable smooth scrolling
c.scrolling.smooth = True

c.auto_save.session = True  # save tabs on quit/restart
c.auto_save.interval = 15000  # autosave interval (in seconds)

# Disable hyperlink auditing (tracking when you click links)
c.content.hyperlink_auditing = False

# ==================== HYPRLAND/WAYLAND SPECIFIC SETTINGS ====================

# Force Wayland backend for better Hyprland integration
# This ensures native Wayland rendering instead of XWayland
c.qt.force_platform = "wayland"

# Enable hardware acceleration for better performance on Wayland
c.qt.args = ["enable-gpu-rasterization", "enable-features=WebContentsForceDark"]

# Window decorations - Hyprland handles these, so disable Qt decorations
c.window.hide_decoration = True

# Enable picture-in-picture mode (works well with Hyprland's floating windows)
c.content.desktop_capture = "ask"
c.content.media.audio_video_capture = "ask"

# Set window title format for better Hyprland window rules
# This helps you create specific Hyprland rules for qutebrowser windows
c.window.title_format = "{perc}{current_title}{title_sep}qutebrowser"
c.tabs.title.format = "{audio}{current_title}"

# Disable Qt's built-in compositor bypass
# This prevents conflicts with Hyprland's compositor
c.qt.workarounds.disable_accelerated_2d_canvas = "auto"

# ==================== DARK MODE KEYBINDINGS ====================

# Toggle dark mode for current page
config.bind(",d", "config-cycle -u colors.webpage.darkmode.enabled")

# Toggle dark mode globally
config.bind(",D", "config-cycle colors.webpage.darkmode.enabled")

# ==================== PERMISSION SHORTCUTS ====================

# Quick permission toggles
config.bind(
    ",js", "config-cycle -u content.javascript.enabled"
)  # Toggle JavaScript for current site
config.bind(
    ",JS", "config-cycle content.javascript.enabled"
)  # Toggle JavaScript globally
config.bind(
    ",po", "config-cycle -u content.javascript.can_open_tabs_automatically"
)  # Toggle popups for site

# ==================== KEYBINDINGS ====================

# Zoom controls for better readability
config.bind("=", "zoom-in")
config.bind("+", "zoom-in")
config.bind("_", "zoom-out")
config.bind("0", "zoom")  # Reset zoom

# Fullscreen toggle
config.bind("F11", "fullscreen")

# Toggle tab bar and status bar for minimal look
config.bind(
    ",b",
    "config-cycle statusbar.show always never ;; config-cycle tabs.show always never",
)

config.bind("=", "cmd-set-text -s :open")
config.bind("h", "history")
config.bind("cs", "cmd-set-text -s :config-source")
config.bind("tH", "config-cycle tabs.show multiple never")
config.bind("sH", "config-cycle statusbar.show always never")
config.bind("T", "hint links tab")
config.bind("pP", "open -- {primary}")
config.bind("pp", "open -- {clipboard}")
config.bind("pt", "open -t -- {clipboard}")
config.bind("tT", "config-cycle tabs.position top left")
config.bind("gJ", "tab-move +")
config.bind("gK", "tab-move -")
config.bind("gm", "tab-move")
