#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
FORCE_BACKUP=0
CHECK_ONLY=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--check] [--force-backup]

Installs kathrynwave:

  - adaptive GTK desktop chrome
  - GNOME Shell panel and dock accents
  - window decoration theme
  - day/night wallpapers
  - GNOME Terminal colors
  - Bash prompt

This does not use sudo, install packages, change icons, change cursors, change
fonts, or change spacing.

Options:
  --dry-run       Print actions without changing settings/files.
  --check         Check compatibility and required settings without changing anything.
  --force-backup  Replace the saved Terminal backup before applying colors.
  -h, --help      Show this help.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

setting() {
  key="$1"
  value="$2"
  run gsettings set "$PROFILE_SCHEMA:$PROFILE_PATH" "$key" "$value"
}

reset_setting() {
  key="$1"
  run gsettings reset "$PROFILE_SCHEMA:$PROFILE_PATH" "$key"
}

remove_kathrynwave_prompt_blocks() {
  local file="$1"
  local label="$2"
  local tmp_file

  [ -f "$file" ] || return 0
  grep -Eq '^# >>> [^[:space:]]+ prompt >>>$' "$file" || return 0

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ remove $label block from $file"
    return 0
  fi

  tmp_file="$(mktemp "$TOOLS_DIR/$label.XXXXXX")"
  awk '
    $0 ~ /^# >>> [^[:space:]]+ prompt >>>$/ { skip = 1; next }
    $0 ~ /^# <<< [^[:space:]]+ prompt <<<$/ { skip = 0; next }
    skip != 1 { print }
  ' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

install_prompt() {
  local begin_marker="# >>> kathrynwave prompt >>>"
  local end_marker="# <<< kathrynwave prompt <<<"
  local bashrc="$HOME/.bashrc"
  local block

  [ -f "$PROMPT_FILE" ] || die "missing prompt file: $PROMPT_FILE"
  [ -f "$bashrc" ] || die "missing ~/.bashrc"

  remove_kathrynwave_prompt_blocks "$bashrc" "bashrc-prompt"

  block="$begin_marker
if [ -f \"$PROMPT_FILE\" ]; then
  . \"$PROMPT_FILE\"
fi
$end_marker"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ append kathrynwave prompt block to $bashrc"
  else
    printf '\n%s\n' "$block" >> "$bashrc"
  fi
}

find_layout() {
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  TOOLS_DIR="$SCRIPT_DIR/.kathrynwave-state"
  PROMPT_FILE="$SCRIPT_DIR/kathrynwave-prompt.bash"
  BACKUP_FILE="$TOOLS_DIR/terminal-profile-backup.dconf"
  BACKUP_META="$TOOLS_DIR/terminal-profile-backup.env"
}

run_desktop_installer() {
  local args=()

  if [ "$CHECK_ONLY" -eq 1 ]; then
    args+=(--check)
  elif [ "$DRY_RUN" -eq 1 ]; then
    args+=(--dry-run)
  fi

  KATHRYNWAVE_REPO_DIR="$SCRIPT_DIR" bash -s -- "${args[@]}" <<'KATHRYNWAVE_EMBEDDED_INSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=0
CHECK_ONLY=0
MODE="night"
ROLLBACK_ON_ERROR=0
BACKUP_DIR_EXISTED_BEFORE=0
SETTINGS_BACKUP_EXISTED_BEFORE=0
GTK3_BACKUP_EXISTED_BEFORE=0
GTK4_BACKUP_EXISTED_BEFORE=0
THEME_TARGET_EXISTED_BEFORE=0
ROLLBACK_THEME_SNAPSHOT=""

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--check]

Installs the experimental kathrynwave desktop color layer:

  - Adaptive GTK theme wrapper based on local Yaru magenta day/night resources
  - Static GNOME Shell top panel accent
  - Mode-neutral GTK3 and GTK4 user-CSS guards
  - GNOME Terminal chrome set to follow the system light/dark switcher
  - GNOME accent color and kathrynwave day/night wallpapers

This script does not touch the GNOME Terminal profile or Bash prompt.
It does not change icons, cursors, fonts, Shell geometry, dock styling, or spacing.

Options:
  --check    Report host compatibility/dependencies without writing files or settings.
  --dry-run  Report dependencies and print the write manifest without changing the host.
  --mode     Apply the day or night palette. Default: night.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

require_gsettings() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  command -v gsettings >/dev/null 2>&1 || die "gsettings is required"
}

require_user_theme_schema() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  gsettings writable org.gnome.shell.extensions.user-theme name >/dev/null 2>&1 ||
    die "GNOME User Themes schema is not available; install/enable the GNOME User Themes Shell extension, then rerun this script"
}

preflight_ok() {
  log "OK: $*"
}

preflight_fail() {
  log "FAIL: $*"
  PREFLIGHT_FAILED=1
}

read_os_release_value() {
  local file="$1"
  local key="$2"

  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

preflight_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    preflight_ok "$command_name command is available"
  else
    preflight_fail "$command_name command is required"
  fi
}

preflight_file() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    preflight_ok "$label exists: $path"
  else
    preflight_fail "$label is missing: $path"
  fi
}

preflight_writable_gsetting() {
  local schema="$1"
  local key="$2"
  local label="$3"

  if ! command -v gsettings >/dev/null 2>&1; then
    preflight_fail "$label cannot be checked because gsettings is missing"
    return 0
  fi

  if gsettings writable "$schema" "$key" >/dev/null 2>&1; then
    preflight_ok "$label is writable"
  else
    preflight_fail "$label is not writable"
  fi
}

preflight_ubuntu_26() {
  local os_release="${KATHRYNWAVE_OS_RELEASE:-/etc/os-release}"
  local id=""
  local version_id=""
  local pretty_name=""

  if [ ! -r "$os_release" ]; then
    preflight_fail "Ubuntu 26 check could not read $os_release"
    return 0
  fi

  id="$(read_os_release_value "$os_release" ID)"
  version_id="$(read_os_release_value "$os_release" VERSION_ID)"
  pretty_name="$(read_os_release_value "$os_release" PRETTY_NAME)"

  if [ "$id" = "ubuntu" ] && case "$version_id" in 26.*) true ;; *) false ;; esac; then
    preflight_ok "Ubuntu 26 detected: ${pretty_name:-Ubuntu $version_id}"
  else
    preflight_fail "Ubuntu 26 is required; detected ${pretty_name:-$id $version_id}"
  fi
}

preflight_theme_target() {
  if [ ! -e "$THEME_TARGET" ]; then
    preflight_ok "theme install path is clear: $THEME_TARGET"
  elif [ -d "$THEME_TARGET" ] && [ -f "$THEME_TARGET/$THEME_MARKER" ]; then
    preflight_ok "existing kathrynwave theme path is repo-owned: $THEME_TARGET"
  elif [ -d "$THEME_TARGET" ]; then
    preflight_fail "$THEME_TARGET exists but is not marked as repo-owned"
  else
    preflight_fail "$THEME_TARGET exists but is not a directory"
  fi
}

run_preflight() {
  PREFLIGHT_FAILED=0

  log "kathrynwave desktop preflight"
  preflight_ubuntu_26
  preflight_command gsettings
  preflight_writable_gsetting org.gnome.desktop.interface gtk-theme "GTK theme setting"
  preflight_writable_gsetting org.gnome.desktop.interface color-scheme "dark-mode color-scheme setting"
  preflight_writable_gsetting org.gnome.desktop.interface accent-color "accent color setting"
  preflight_writable_gsetting org.gnome.desktop.background picture-uri "light wallpaper setting"
  preflight_writable_gsetting org.gnome.desktop.background picture-uri-dark "dark wallpaper setting"
  preflight_writable_gsetting org.gnome.shell.extensions.user-theme name "User Themes Shell theme setting"
  preflight_writable_gsetting org.gnome.desktop.wm.preferences theme "window-manager decoration theme setting"
  preflight_writable_gsetting org.gnome.Terminal.Legacy.Settings theme-variant "GNOME Terminal chrome variant setting"
  preflight_file "$THEME_DIR/gtk-3.0/yaru-day/gtk.css" "kathrynwave GTK3 day base CSS"
  preflight_file "$THEME_DIR/gtk-3.0/yaru-night/gtk-dark.css" "kathrynwave GTK3 night base CSS"
  preflight_file "$THEME_DIR/gtk-4.0/yaru-day/gtk.css" "kathrynwave GTK4 day base CSS"
  preflight_file "$THEME_DIR/gtk-4.0/yaru-night/gtk-dark.css" "kathrynwave GTK4 night base CSS"
  preflight_file "$THEME_DIR/gtk-3.0/user-overrides.css" "kathrynwave GTK3 user CSS"
  preflight_file "$THEME_DIR/gtk-3.0/user-overrides-dark.css" "kathrynwave GTK3 dark user CSS"
  preflight_file "$THEME_DIR/gtk-3.0/user-live-overrides.css" "kathrynwave GTK3 live guard CSS"
  preflight_file "$THEME_DIR/gtk-4.0/user-overrides.css" "kathrynwave GTK4 user CSS"
  preflight_file "$THEME_DIR/gtk-4.0/user-overrides-dark.css" "kathrynwave GTK4 dark user CSS"
  preflight_file "$THEME_DIR/gtk-4.0/user-live-overrides.css" "kathrynwave GTK4 live guard CSS"
  preflight_file "$THEME_DIR/gnome-shell/gnome-shell.css" "kathrynwave Shell top-panel CSS"
  preflight_file "$DAY_WALLPAPER_FILE" "kathrynwave day wallpaper"
  preflight_file "$NIGHT_WALLPAPER_FILE" "kathrynwave night wallpaper"
  preflight_theme_target

  if [ "$PREFLIGHT_FAILED" -eq 0 ]; then
    log "Preflight passed."
    return 0
  fi

  log "Preflight failed. Fix the items above, then rerun this script."
  return 1
}

is_safe_setting_value() {
  printf '%s\n' "$1" | grep -Eq "^'([^'\\\\]|\\\\.)*'$|^[A-Za-z0-9._+-]+$"
}

read_backup_value() {
  local file="$1"
  local key="$2"
  local default_value="$3"
  local value

  if [ ! -f "$file" ]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  value="$(awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file")"
  if [ -n "$value" ]; then
    is_safe_setting_value "$value" || die "invalid $key in $file"
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

validate_settings_backup() {
  local backup_file="$BACKUP_DIR/settings.env"

  [ -f "$backup_file" ] || return 0

  read_backup_value "$backup_file" GTK_THEME_NAME "'Yaru-magenta-dark'" >/dev/null
  read_backup_value "$backup_file" COLOR_SCHEME "'prefer-dark'" >/dev/null
  read_backup_value "$backup_file" USER_THEME_NAME "''" >/dev/null
  read_backup_value "$backup_file" WM_THEME_NAME "'Adwaita'" >/dev/null
  read_backup_value "$backup_file" TERMINAL_THEME_VARIANT "'dark'" >/dev/null
  read_backup_value "$backup_file" ACCENT_COLOR "'pink'" >/dev/null
  read_backup_value "$backup_file" BACKGROUND_PICTURE_URI "''" >/dev/null
  read_backup_value "$backup_file" BACKGROUND_PICTURE_URI_DARK "''" >/dev/null
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

validate_sources() {
  [ -f "$THEME_DIR/gtk-3.0/user-overrides.css" ] || die "missing GTK3 user CSS"
  [ -f "$THEME_DIR/gtk-3.0/user-overrides-dark.css" ] || die "missing GTK3 dark user CSS"
  [ -f "$THEME_DIR/gtk-3.0/user-live-overrides.css" ] || die "missing GTK3 live guard CSS"
  [ -f "$THEME_DIR/gtk-4.0/user-overrides.css" ] || die "missing GTK4 user CSS"
  [ -f "$THEME_DIR/gtk-4.0/user-overrides-dark.css" ] || die "missing GTK4 dark user CSS"
  [ -f "$THEME_DIR/gtk-4.0/user-live-overrides.css" ] || die "missing GTK4 live guard CSS"
  [ -f "$THEME_DIR/gtk-3.0/gtk.css" ] || die "missing GTK3 theme CSS"
  [ -f "$THEME_DIR/gtk-3.0/gtk-dark.css" ] || die "missing GTK3 dark theme CSS"
  [ -f "$THEME_DIR/gtk-4.0/gtk.css" ] || die "missing GTK4 theme CSS"
  [ -f "$THEME_DIR/gtk-4.0/gtk-dark.css" ] || die "missing GTK4 dark theme CSS"
  [ -f "$THEME_DIR/gtk-3.0/yaru-day/gtk.css" ] || die "missing GTK3 day base CSS"
  [ -f "$THEME_DIR/gtk-3.0/yaru-night/gtk-dark.css" ] || die "missing GTK3 night base CSS"
  [ -f "$THEME_DIR/gtk-4.0/yaru-day/gtk.css" ] || die "missing GTK4 day base CSS"
  [ -f "$THEME_DIR/gtk-4.0/yaru-night/gtk-dark.css" ] || die "missing GTK4 night base CSS"
  [ -f "$THEME_DIR/gnome-shell/gnome-shell.css" ] || die "missing Shell top-panel CSS"
  [ -f "$THEME_DIR/index.theme" ] || die "missing theme index"
  [ -f "$DAY_WALLPAPER_FILE" ] || die "missing day wallpaper"
  [ -f "$NIGHT_WALLPAPER_FILE" ] || die "missing night wallpaper"
  case "$DAY_WALLPAPER_FILE" in
    *"'"*) die "day wallpaper path cannot contain single quotes: $DAY_WALLPAPER_FILE" ;;
  esac
  case "$NIGHT_WALLPAPER_FILE" in
    *"'"*) die "night wallpaper path cannot contain single quotes: $NIGHT_WALLPAPER_FILE" ;;
  esac
}

print_dry_run_manifest() {
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local day_wallpaper_value
  local night_wallpaper_value

  [ "$DRY_RUN" -eq 1 ] || return 0
  day_wallpaper_value="$(wallpaper_setting_value "$DAY_WALLPAPER_FILE")"
  night_wallpaper_value="$(wallpaper_setting_value "$NIGHT_WALLPAPER_FILE")"

  log "DRY-RUN WRITE MANIFEST"
  log "  mode: $MODE"
  log "  repo backup dir: $BACKUP_DIR"
  log "  shell marker: $THEME_TARGET/$THEME_MARKER"
  log "  source palette: $THEME_DIR (adaptive day/night)"
  log "  GTK theme files: $THEME_TARGET/gtk-3.0 and gtk-4.0"
  log "  GTK extracted Yaru resources: $THEME_TARGET/gtk-3.0/yaru-day, yaru-night and gtk-4.0/yaru-day, yaru-night"
  log "  Shell top-panel CSS: $THEME_TARGET/gnome-shell/gnome-shell.css"
  log "  window decoration theme: $THEME_TARGET/metacity-1"
  log "  GTK3 user CSS: $config_home/gtk-3.0/gtk.css"
  log "  GTK4 user CSS: $config_home/gtk-4.0/gtk.css"
  log "  day wallpaper file: $DAY_WALLPAPER_FILE"
  log "  night wallpaper file: $NIGHT_WALLPAPER_FILE"
  log "  gsettings set: org.gnome.desktop.interface gtk-theme $THEME_NAME"
  log "  gsettings set: org.gnome.desktop.interface color-scheme $COLOR_SCHEME"
  log "  gsettings set: org.gnome.desktop.interface accent-color $ACCENT_COLOR"
  log "  gsettings set: org.gnome.desktop.background picture-uri $day_wallpaper_value"
  log "  gsettings set: org.gnome.desktop.background picture-uri-dark $night_wallpaper_value"
  log "  gsettings set: org.gnome.shell.extensions.user-theme name $SHELL_THEME_NAME"
  log "  gsettings set: org.gnome.desktop.wm.preferences theme $WM_THEME_NAME"
  log "  gsettings set: org.gnome.Terminal.Legacy.Settings theme-variant $TERMINAL_THEME_VARIANT"
}

validate_theme_target() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ verify $THEME_TARGET is absent or owned by a previous kathrynwave install"
    return 0
  fi

  [ ! -e "$THEME_TARGET" ] && return 0
  [ -d "$THEME_TARGET" ] || die "$THEME_TARGET exists but is not a directory"
  [ -f "$THEME_TARGET/$THEME_MARKER" ] || die "$THEME_TARGET already exists and is not marked as repo-owned"
}

capture_rollback_state() {
  [ "$DRY_RUN" -eq 1 ] && return 0

  [ -d "$BACKUP_DIR" ] && BACKUP_DIR_EXISTED_BEFORE=1
  [ -f "$BACKUP_DIR/settings.env" ] && SETTINGS_BACKUP_EXISTED_BEFORE=1
  [ -f "$BACKUP_DIR/gtk-3.0.gtk.css" ] && GTK3_BACKUP_EXISTED_BEFORE=1
  [ -f "$BACKUP_DIR/gtk-4.0.gtk.css" ] && GTK4_BACKUP_EXISTED_BEFORE=1

  if [ -d "$THEME_TARGET" ]; then
    THEME_TARGET_EXISTED_BEFORE=1
    ROLLBACK_THEME_SNAPSHOT="$(mktemp -d "$TOOLS_DIR/desktop-theme-before-install.XXXXXX")"
    cp -a "$THEME_TARGET/." "$ROLLBACK_THEME_SNAPSHOT/"
  fi
}

cleanup_rollback_state() {
  if [ -n "$ROLLBACK_THEME_SNAPSHOT" ] && [ -d "$ROLLBACK_THEME_SNAPSHOT" ]; then
    rm -rf "$ROLLBACK_THEME_SNAPSHOT"
  fi
}

remove_marked_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local label="$4"
  local tmp_file

  [ -f "$file" ] || return 0
  grep -Fq "$begin" "$file" || return 0

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ remove $label block from $file"
    return 0
  fi

  tmp_file="$(mktemp "$TOOLS_DIR/$label.XXXXXX")"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

remove_if_whitespace_only() {
  local file="$1"

  [ -f "$file" ] || return 0
  if grep -q '[^[:space:]]' "$file"; then
    return 0
  fi

  run rm -f "$file"
}

cleanup_legacy_gtk_import() {
  local gtk_version="$1"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_dir="$config_home/gtk-$gtk_version.0"
  local gtk_css="$config_dir/gtk.css"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ remove legacy GTK$gtk_version user-CSS import from $gtk_css, if present"
    return 0
  fi

  remove_kathrynwave_gtk_blocks "$gtk_version" "$gtk_css" "gtk-$gtk_version-colors"
  remove_if_whitespace_only "$gtk_css"
}

strip_gtk_user_blocks() {
  local gtk_version="$1"
  local file="$2"

  awk \
    -v gtk_version="$gtk_version" '
      $0 ~ "^/\\* >>> [^[:space:]]+ gtk-" gtk_version "\\.0 (user )?colors >>> \\*/$" { skip = 1; next }
      $0 ~ "^/\\* <<< [^[:space:]]+ gtk-" gtk_version "\\.0 (user )?colors <<< \\*/$" { skip = 0; next }
      skip != 1 { print }
    ' "$file"
}

remove_kathrynwave_gtk_blocks() {
  local gtk_version="$1"
  local file="$2"
  local label="$3"
  local tmp_file

  [ -f "$file" ] || return 0
  grep -Eq "^/\\* >>> [^[:space:]]+ gtk-$gtk_version\\.0 (user )?colors >>> \\*/$" "$file" || return 0

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ remove $label block from $file"
    return 0
  fi

  tmp_file="$(mktemp "$TOOLS_DIR/$label.XXXXXX")"
  strip_gtk_user_blocks "$gtk_version" "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

install_gtk_user_css() {
  local gtk_version="$1"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_dir="$config_home/gtk-$gtk_version.0"
  local gtk_css="$config_dir/gtk.css"
  local source_css="$THEME_DIR/gtk-$gtk_version.0/user-live-overrides.css"
  local backup_css="$BACKUP_DIR/gtk-$gtk_version.0.gtk.css"
  local marker_start="/* >>> kathrynwave gtk-$gtk_version.0 user colors >>> */"
  local marker_end="/* <<< kathrynwave gtk-$gtk_version.0 user colors <<< */"
  local tmp_file

  [ -f "$source_css" ] || die "missing GTK$gtk_version user CSS: $source_css"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ preserve original GTK$gtk_version user CSS once: $backup_css"
    log "+ install marked kathrynwave GTK$gtk_version user CSS block into: $gtk_css"
    return 0
  fi

  mkdir -p "$config_dir" "$BACKUP_DIR"

  if [ ! -f "$backup_css" ]; then
    if [ -f "$gtk_css" ]; then
      strip_gtk_user_blocks "$gtk_version" "$gtk_css" > "$backup_css"
    else
      : > "$backup_css"
    fi
  fi

  tmp_file="$(mktemp "$TOOLS_DIR/gtk-$gtk_version-user-colors.XXXXXX")"
  {
    printf '%s\n' "$marker_start"
    cat "$source_css"
    printf '%s\n\n' "$marker_end"
    if [ -f "$gtk_css" ]; then
      strip_gtk_user_blocks "$gtk_version" "$gtk_css"
    fi
  } > "$tmp_file"
  mv "$tmp_file" "$gtk_css"
}

save_settings_backup() {
  local backup_file="$BACKUP_DIR/settings.env"
  local old_shell_backup="$BACKUP_DIR/user-theme-name.env"
  local gtk_theme
  local color_scheme
  local shell_theme
  local wm_theme
  local terminal_theme_variant
  local accent_color
  local background_picture_uri
  local background_picture_uri_dark

  require_gsettings

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ preserve current GTK/Shell/window-manager/accent/wallpaper settings once to $backup_file"
    return 0
  fi

  mkdir -p "$BACKUP_DIR"

  if [ -f "$backup_file" ]; then
    if ! awk -F= '$1 == "WM_THEME_NAME" { found = 1 } END { exit(found ? 0 : 1) }' "$backup_file"; then
      wm_theme="$(gsettings get org.gnome.desktop.wm.preferences theme 2>/dev/null || printf "'Adwaita'")"
      printf 'WM_THEME_NAME=%s\n' "$wm_theme" >> "$backup_file"
    fi
    if ! awk -F= '$1 == "TERMINAL_THEME_VARIANT" { found = 1 } END { exit(found ? 0 : 1) }' "$backup_file"; then
      terminal_theme_variant="$(gsettings get org.gnome.Terminal.Legacy.Settings theme-variant 2>/dev/null || printf "'dark'")"
      printf 'TERMINAL_THEME_VARIANT=%s\n' "$terminal_theme_variant" >> "$backup_file"
    fi
    if ! awk -F= '$1 == "ACCENT_COLOR" { found = 1 } END { exit(found ? 0 : 1) }' "$backup_file"; then
      accent_color="$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null || printf "'pink'")"
      printf 'ACCENT_COLOR=%s\n' "$accent_color" >> "$backup_file"
    fi
    if ! awk -F= '$1 == "BACKGROUND_PICTURE_URI" { found = 1 } END { exit(found ? 0 : 1) }' "$backup_file"; then
      background_picture_uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || printf "''")"
      printf 'BACKGROUND_PICTURE_URI=%s\n' "$background_picture_uri" >> "$backup_file"
    fi
    if ! awk -F= '$1 == "BACKGROUND_PICTURE_URI_DARK" { found = 1 } END { exit(found ? 0 : 1) }' "$backup_file"; then
      background_picture_uri_dark="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || printf "''")"
      printf 'BACKGROUND_PICTURE_URI_DARK=%s\n' "$background_picture_uri_dark" >> "$backup_file"
    fi
    return 0
  fi

  gtk_theme="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || printf "'Yaru-magenta-dark'")"
  color_scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || printf "'prefer-dark'")"
  if [ -f "$old_shell_backup" ]; then
    shell_theme="$(read_backup_value "$old_shell_backup" USER_THEME_NAME "''")"
  else
    shell_theme="$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null || printf "''")"
  fi
  wm_theme="$(gsettings get org.gnome.desktop.wm.preferences theme 2>/dev/null || printf "'Adwaita'")"
  terminal_theme_variant="$(gsettings get org.gnome.Terminal.Legacy.Settings theme-variant 2>/dev/null || printf "'dark'")"
  accent_color="$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null || printf "'pink'")"
  background_picture_uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || printf "''")"
  background_picture_uri_dark="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || printf "''")"

  {
    printf 'GTK_THEME_NAME=%s\n' "$gtk_theme"
    printf 'COLOR_SCHEME=%s\n' "$color_scheme"
    printf 'USER_THEME_NAME=%s\n' "$shell_theme"
    printf 'WM_THEME_NAME=%s\n' "$wm_theme"
    printf 'TERMINAL_THEME_VARIANT=%s\n' "$terminal_theme_variant"
    printf 'ACCENT_COLOR=%s\n' "$accent_color"
    printf 'BACKGROUND_PICTURE_URI=%s\n' "$background_picture_uri"
    printf 'BACKGROUND_PICTURE_URI_DARK=%s\n' "$background_picture_uri_dark"
  } > "$backup_file"
}

install_theme_files() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ install adaptive GTK theme files, static Shell accents, and static window decoration theme to $THEME_TARGET"
    return 0
  fi

  mkdir -p "$THEME_TARGET"
  rm -rf "$THEME_TARGET/gtk-3.0" "$THEME_TARGET/gtk-4.0" "$THEME_TARGET/gnome-shell" "$THEME_TARGET/metacity-1"
  rm -f "$THEME_TARGET/index.theme"
  cp -a "$THEME_DIR/gtk-3.0" "$THEME_TARGET/"
  cp -a "$THEME_DIR/gtk-4.0" "$THEME_TARGET/"
  cp -a "$THEME_DIR/gnome-shell" "$THEME_TARGET/"
  cp -a "$THEME_DIR/metacity-1" "$THEME_TARGET/"
  cp "$THEME_DIR/index.theme" "$THEME_TARGET/index.theme"
  : > "$THEME_TARGET/$THEME_MARKER"
}

apply_theme_settings() {
  local day_wallpaper_value
  local night_wallpaper_value

  require_gsettings
  day_wallpaper_value="$(wallpaper_setting_value "$DAY_WALLPAPER_FILE")"
  night_wallpaper_value="$(wallpaper_setting_value "$NIGHT_WALLPAPER_FILE")"

  run gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME"
  run gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME"
  run gsettings set org.gnome.desktop.interface accent-color "$ACCENT_COLOR"
  run gsettings set org.gnome.desktop.background picture-uri "$day_wallpaper_value"
  run gsettings set org.gnome.desktop.background picture-uri-dark "$night_wallpaper_value"
  run gsettings set org.gnome.shell.extensions.user-theme name "$SHELL_THEME_NAME"
  run gsettings set org.gnome.desktop.wm.preferences theme "$WM_THEME_NAME"
  run gsettings set org.gnome.Terminal.Legacy.Settings theme-variant "$TERMINAL_THEME_VARIANT"
}

wallpaper_setting_value() {
  printf "'file://%s'\n" "$1"
}

remove_repo_owned_theme_dir() {
  local target="$1"
  local marker="$2"

  [ -d "$target" ] || return 0

  if [ ! -f "$marker" ]; then
    log "Skipping $target because it is not marked as repo-owned."
    return 0
  fi

  run rm -rf "$target"
}

cleanup_legacy_theme_files() {
  remove_repo_owned_theme_dir "$LEGACY_THEME_TARGET" "$LEGACY_THEME_MARKER"
}

restore_settings_for_failed_install() {
  local backup_file="$BACKUP_DIR/settings.env"
  local old_shell_backup="$BACKUP_DIR/user-theme-name.env"
  local gtk_theme="'Yaru-magenta-dark'"
  local color_scheme="'prefer-dark'"
  local shell_theme="''"
  local wm_theme="'Adwaita'"
  local terminal_theme_variant="'dark'"
  local accent_color="'pink'"
  local background_picture_uri=""
  local background_picture_uri_dark=""

  command -v gsettings >/dev/null 2>&1 || return 0

  if [ -f "$backup_file" ]; then
    gtk_theme="$(read_backup_value "$backup_file" GTK_THEME_NAME "$gtk_theme")" || return 0
    color_scheme="$(read_backup_value "$backup_file" COLOR_SCHEME "$color_scheme")" || return 0
    shell_theme="$(read_backup_value "$backup_file" USER_THEME_NAME "$shell_theme")" || return 0
    wm_theme="$(read_backup_value "$backup_file" WM_THEME_NAME "$wm_theme")" || return 0
    terminal_theme_variant="$(read_backup_value "$backup_file" TERMINAL_THEME_VARIANT "$terminal_theme_variant")" || return 0
    accent_color="$(read_backup_value "$backup_file" ACCENT_COLOR "$accent_color")" || return 0
    background_picture_uri="$(read_backup_value "$backup_file" BACKGROUND_PICTURE_URI "$background_picture_uri")" || return 0
    background_picture_uri_dark="$(read_backup_value "$backup_file" BACKGROUND_PICTURE_URI_DARK "$background_picture_uri_dark")" || return 0
  elif [ -f "$old_shell_backup" ]; then
    shell_theme="$(read_backup_value "$old_shell_backup" USER_THEME_NAME "$shell_theme")" || return 0
  fi

  gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface accent-color "$accent_color" >/dev/null 2>&1 || true
  [ -n "$background_picture_uri" ] && gsettings set org.gnome.desktop.background picture-uri "$background_picture_uri" >/dev/null 2>&1 || true
  [ -n "$background_picture_uri_dark" ] && gsettings set org.gnome.desktop.background picture-uri-dark "$background_picture_uri_dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.shell.extensions.user-theme name "$shell_theme" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.wm.preferences theme "$wm_theme" >/dev/null 2>&1 || true
  gsettings set org.gnome.Terminal.Legacy.Settings theme-variant "$terminal_theme_variant" >/dev/null 2>&1 || true
}

restore_gtk_for_failed_install() {
  local gtk_version="$1"
  local backup_existed="$2"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_dir="$config_home/gtk-$gtk_version.0"
  local gtk_css="$config_dir/gtk.css"
  local backup_css="$BACKUP_DIR/gtk-$gtk_version.0.gtk.css"

  if [ -f "$backup_css" ]; then
    mkdir -p "$config_dir"
    if [ -s "$backup_css" ]; then
      cp "$backup_css" "$gtk_css" || true
    else
      rm -f "$gtk_css" || true
    fi
  else
    remove_marked_block "$gtk_css" \
      "/* >>> kathrynwave gtk-$gtk_version.0 user colors >>> */" \
      "/* <<< kathrynwave gtk-$gtk_version.0 user colors <<< */" \
      "gtk-$gtk_version-user-colors" || true
    remove_if_whitespace_only "$gtk_css" || true
  fi

  if [ "$backup_existed" -eq 0 ]; then
    rm -f "$backup_css" || true
  fi
}

restore_theme_files_for_failed_install() {
  if [ "$THEME_TARGET_EXISTED_BEFORE" -eq 1 ]; then
    rm -rf "$THEME_TARGET" || true
    mkdir -p "$THEME_TARGET" || true
    if [ -n "$ROLLBACK_THEME_SNAPSHOT" ] && [ -d "$ROLLBACK_THEME_SNAPSHOT" ]; then
      cp -a "$ROLLBACK_THEME_SNAPSHOT/." "$THEME_TARGET/" || true
    fi
  elif [ -e "$THEME_TARGET" ]; then
    rm -rf "$THEME_TARGET" || true
  fi
}

cleanup_backups_for_failed_install() {
  if [ "$SETTINGS_BACKUP_EXISTED_BEFORE" -eq 0 ]; then
    rm -f "$BACKUP_DIR/settings.env" || true
  fi

  if [ "$BACKUP_DIR_EXISTED_BEFORE" -eq 0 ]; then
    rmdir "$BACKUP_DIR" 2>/dev/null || true
  fi
}

rollback_failed_install() {
  local status="$1"

  [ "$ROLLBACK_ON_ERROR" -eq 1 ] || exit "$status"
  ROLLBACK_ON_ERROR=0
  set +e

  log "kathrynwave desktop install failed; rolling back partial changes." >&2
  restore_settings_for_failed_install
  restore_gtk_for_failed_install 3 "$GTK3_BACKUP_EXISTED_BEFORE"
  restore_gtk_for_failed_install 4 "$GTK4_BACKUP_EXISTED_BEFORE"
  restore_theme_files_for_failed_install
  cleanup_backups_for_failed_install
  cleanup_rollback_state

  exit "$status"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --check)
      CHECK_ONLY=1
      ;;
    --mode)
      shift
      [ $# -gt 0 ] || die "--mode requires day or night"
      MODE="$1"
      ;;
    --mode=*)
      MODE="${1#--mode=}"
      ;;
    --day)
      MODE="day"
      ;;
    --night)
      MODE="night"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[ "$(id -u)" -ne 0 ] || die "do not run as root or with sudo"
[ -n "${HOME:-}" ] || die "HOME is not set"

SCRIPT_DIR="${KATHRYNWAVE_REPO_DIR:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
REPO_DIR="$SCRIPT_DIR"
TOOLS_DIR="$SCRIPT_DIR/.kathrynwave-state"
DAY_WALLPAPER_FILE="$REPO_DIR/wallpapers/kathrynwave-wallpaper-06.jpg"
NIGHT_WALLPAPER_FILE="$REPO_DIR/wallpapers/kathrynwave-wallpaper-01.jpg"
BACKUP_DIR="$TOOLS_DIR/desktop-color-backup"
THEME_NAME="kathrynwave"
THEME_DIR="$REPO_DIR/theme/kathrynwave"
ACCENT_COLOR="pink"
SHELL_THEME_NAME="kathrynwave"
WM_THEME_NAME="kathrynwave"
TERMINAL_THEME_VARIANT="system"
THEME_MARKER=".kathrynwave"
THEME_TARGET="$HOME/.themes/$THEME_NAME"
LEGACY_THEME_TARGET="$HOME/.themes/${THEME_NAME%wave}-theme"
LEGACY_THEME_MARKER="$LEGACY_THEME_TARGET/.${THEME_NAME%wave}-theme"

case "$MODE" in
  day)
    COLOR_SCHEME="prefer-light"
    ;;
  night)
    COLOR_SCHEME="prefer-dark"
    ;;
  *)
    die "unknown mode: $MODE"
    ;;
esac

run_preflight || exit 1
[ "$CHECK_ONLY" -eq 0 ] || exit 0
validate_sources
print_dry_run_manifest
require_gsettings
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$TOOLS_DIR"
fi
validate_theme_target
capture_rollback_state
ROLLBACK_ON_ERROR=1
trap 'rollback_failed_install "$?"' ERR
save_settings_backup
validate_settings_backup
install_theme_files
install_gtk_user_css 3
install_gtk_user_css 4
apply_theme_settings
ROLLBACK_ON_ERROR=0
trap - ERR
cleanup_rollback_state
cleanup_legacy_theme_files

if [ "$DRY_RUN" -eq 1 ]; then
  log "kathrynwave desktop dry-run complete. No files or settings were changed."
else
  log "kathrynwave desktop colors installed."
  log "Close and reopen GTK apps if they do not repaint."
fi
KATHRYNWAVE_EMBEDDED_INSTALL
}

check_terminal_layer() {
  command -v dconf >/dev/null 2>&1 || die "dconf is required"
  [ -f "$PROMPT_FILE" ] || die "missing prompt file: $PROMPT_FILE"
  PROFILE_UUID="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")"
  [ -n "$PROFILE_UUID" ] || die "could not determine default GNOME Terminal profile"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --check)
      CHECK_ONLY=1
      ;;
    --force-backup)
      FORCE_BACKUP=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[ "$(id -u)" -ne 0 ] || die "do not run this installer as root or with sudo"
[ -n "${HOME:-}" ] || die "HOME is not set"
command -v gsettings >/dev/null 2>&1 || die "gsettings is required"

find_layout

if [ "$CHECK_ONLY" -eq 1 ]; then
  run_desktop_installer
  check_terminal_layer
  log "kathrynwave install check passed."
  exit 0
fi

run_desktop_installer

command -v dconf >/dev/null 2>&1 || die "dconf is required"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$TOOLS_DIR"
fi

PROFILE_UUID="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")"
[ -n "$PROFILE_UUID" ] || die "could not determine default GNOME Terminal profile"

PROFILE_SCHEMA="org.gnome.Terminal.Legacy.Profile"
PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$PROFILE_UUID/"

if [ "$DRY_RUN" -eq 1 ]; then
  log "+ inspect default Terminal profile: $PROFILE_UUID"
fi

if [ "$FORCE_BACKUP" -eq 1 ] || [ ! -f "$BACKUP_FILE" ] || [ ! -f "$BACKUP_META" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ dconf dump $PROFILE_PATH > $BACKUP_FILE"
    log "+ write backup metadata to $BACKUP_META"
  else
    dconf dump "$PROFILE_PATH" > "$BACKUP_FILE"
    {
      printf 'PROFILE_UUID=%q\n' "$PROFILE_UUID"
      printf 'PROFILE_PATH=%q\n' "$PROFILE_PATH"
    } > "$BACKUP_META"
  fi
else
  log "Preserving existing Terminal backup: $BACKUP_FILE"
fi

reset_setting visible-name
reset_setting use-system-font
reset_setting font
reset_setting cell-height-scale
reset_setting cell-width-scale
reset_setting use-theme-transparency
reset_setting use-transparent-background
reset_setting background-transparency-percent

PALETTE="['#2a0646', '#ff3864', '#24f9a6', '#ffb000', '#2f6dff', '#ff2d95', '#00d9ff', '#ffe6f7', '#5a3f7a', '#ff5c8a', '#75ffc8', '#ffd166', '#5b8cff', '#9d4dff', '#55f3ff', '#ffffff']"

setting use-theme-colors false
setting use-theme-transparency false
setting use-transparent-background false
setting background-transparency-percent 0
setting foreground-color "'#ffe6f7'"
setting background-color "'#2a0646'"
setting palette "$PALETTE"
setting bold-color-same-as-fg false
setting bold-color "'#ffffff'"
setting bold-is-bright true
setting cursor-colors-set true
setting cursor-background-color "'#ffb000'"
setting cursor-foreground-color "'#2a0646'"
setting highlight-colors-set true
setting highlight-background-color "'#5a1b58'"
setting highlight-foreground-color "'#ffffff'"

install_prompt

log "kathrynwave installed."
log "Use Ubuntu Appearance to switch light and dark mode."
