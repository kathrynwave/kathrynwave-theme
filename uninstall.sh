#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
KEEP_BACKUP=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--dry-run] [--keep-backup]

Uninstalls kathrynwave and restores saved desktop and Terminal settings.

Options:
  --dry-run      Print actions without changing settings/files.
  --keep-backup  Restore settings but keep backup files.
  -h, --help     Show this help.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'uninstall.sh: %s\n' "$*" >&2
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

reset_touched_terminal_keys() {
  local keys="
visible-name
use-theme-colors
foreground-color
background-color
palette
bold-color-same-as-fg
bold-color
bold-is-bright
cursor-colors-set
cursor-background-color
cursor-foreground-color
highlight-colors-set
highlight-background-color
highlight-foreground-color
use-theme-transparency
use-transparent-background
background-transparency-percent
use-system-font
font
cell-height-scale
cell-width-scale
"

  for key in $keys; do
    run gsettings reset "$PROFILE_SCHEMA:$PROFILE_PATH" "$key"
  done
}

restore_terminal() {
  PROFILE_SCHEMA="org.gnome.Terminal.Legacy.Profile"

  if [ -f "$BACKUP_FILE" ] && [ -f "$BACKUP_META" ]; then
    # shellcheck disable=SC1090
    . "$BACKUP_META"
    [ -n "${PROFILE_PATH:-}" ] || die "backup metadata does not include PROFILE_PATH"

    reset_touched_terminal_keys

    if [ "$DRY_RUN" -eq 1 ]; then
      log "+ dconf load $PROFILE_PATH < $BACKUP_FILE"
    else
      dconf load "$PROFILE_PATH" < "$BACKUP_FILE"
    fi

    if [ "$KEEP_BACKUP" -eq 0 ]; then
      run rm -f "$BACKUP_FILE" "$BACKUP_META"
    fi

    log "GNOME Terminal profile restored from kathrynwave backup."
    return 0
  fi

  PROFILE_UUID="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")"
  [ -n "$PROFILE_UUID" ] || die "could not determine default GNOME Terminal profile"
  PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$PROFILE_UUID/"

  reset_touched_terminal_keys
  log "No Terminal backup found; reset kathrynwave Terminal keys to schema defaults."
}

remove_prompt() {
  local bashrc="$HOME/.bashrc"

  remove_kathrynwave_prompt_blocks "$bashrc" "bashrc-prompt"
}

find_layout() {
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  TOOLS_DIR="$SCRIPT_DIR/.kathrynwave-state"
  BACKUP_FILE="$TOOLS_DIR/terminal-profile-backup.dconf"
  BACKUP_META="$TOOLS_DIR/terminal-profile-backup.env"
}

run_desktop_uninstaller() {
  local args=()

  [ "$DRY_RUN" -eq 1 ] && args+=(--dry-run)
  [ "$KEEP_BACKUP" -eq 1 ] && args+=(--keep-backup)

  KATHRYNWAVE_REPO_DIR="$SCRIPT_DIR" bash -s -- "${args[@]}" <<'KATHRYNWAVE_EMBEDDED_UNINSTALL'
#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
KEEP_BACKUP=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--dry-run] [--keep-backup]

Removes/restores the experimental kathrynwave desktop color layer.
This script does not touch the GNOME Terminal profile or Bash prompt.
It does not change icons, cursors, fonts, or spacing.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'uninstall.sh: %s\n' "$*" >&2
  exit 1
}

require_gsettings() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  command -v gsettings >/dev/null 2>&1 || die "gsettings is required"
}

print_dry_run_manifest() {
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

  [ "$DRY_RUN" -eq 1 ] || return 0

  log "DRY-RUN UNINSTALL WRITE MANIFEST"
  log "  restore gsettings: org.gnome.desktop.interface gtk-theme <backed-up-or-default-theme>"
  log "  restore gsettings: org.gnome.desktop.interface color-scheme <backed-up-or-default-scheme>"
  log "  restore gsettings: org.gnome.desktop.interface accent-color <backed-up-if-present>"
  log "  restore gsettings: org.gnome.desktop.background picture-uri <backed-up-if-present>"
  log "  restore gsettings: org.gnome.desktop.background picture-uri-dark <backed-up-if-present>"
  log "  restore gsettings: org.gnome.shell.extensions.user-theme name <backed-up-or-empty-theme>"
  log "  restore gsettings: org.gnome.desktop.wm.preferences theme <backed-up-or-default-theme>"
  log "  restore gsettings: org.gnome.Terminal.Legacy.Settings theme-variant <backed-up-or-dark>"
  log "  restore/remove GTK3 user CSS: $config_home/gtk-3.0/gtk.css"
  log "  restore/remove GTK4 user CSS: $config_home/gtk-4.0/gtk.css"
  log "  remove repo-owned shell marker: $THEME_TARGET/$THEME_MARKER"
  log "  remove repo-owned GTK theme files: $THEME_TARGET/gtk-3.0 and gtk-4.0"
  log "  remove repo-owned shell CSS: $THEME_TARGET/gnome-shell/gnome-shell.css"
  log "  remove repo-owned window decoration theme: $THEME_TARGET/metacity-1"
  log "  remove backup dir unless --keep-backup: $BACKUP_DIR"
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

backup_has_key() {
  local file="$1"
  local key="$2"

  [ -f "$file" ] || return 1
  awk -F= -v key="$key" '$1 == key { found = 1 } END { exit(found ? 0 : 1) }' "$file"
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

strip_kathrynwave_gtk_blocks() {
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
  strip_kathrynwave_gtk_blocks "$gtk_version" "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

restore_gtk_user_css() {
  local gtk_version="$1"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_dir="$config_home/gtk-$gtk_version.0"
  local gtk_css="$config_dir/gtk.css"
  local backup_css="$BACKUP_DIR/gtk-$gtk_version.0.gtk.css"

  if [ -f "$gtk_css" ]; then
    remove_kathrynwave_gtk_blocks "$gtk_version" "$gtk_css" "gtk-$gtk_version-user-colors"
    remove_if_whitespace_only "$gtk_css"
  elif [ -f "$backup_css" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "+ restore $gtk_css from $backup_css"
    else
      mkdir -p "$config_dir"
      if [ -s "$backup_css" ]; then
        cp "$backup_css" "$gtk_css"
      else
        rm -f "$gtk_css"
      fi
    fi
  else
    remove_kathrynwave_gtk_blocks "$gtk_version" "$gtk_css" "gtk-$gtk_version-user-colors"
    remove_if_whitespace_only "$gtk_css"
  fi
}

restore_theme_settings() {
  local backup_file="$BACKUP_DIR/settings.env"
  local old_shell_backup="$BACKUP_DIR/user-theme-name.env"
  local gtk_theme="'Yaru-magenta-dark'"
  local color_scheme="'prefer-dark'"
  local shell_theme="''"
  local wm_theme="'Adwaita'"
  local terminal_theme_variant="'dark'"
  local accent_color=""
  local background_picture_uri=""
  local background_picture_uri_dark=""
  local restore_accent=0
  local restore_background=0

  require_gsettings

  if [ -f "$backup_file" ]; then
    gtk_theme="$(read_backup_value "$backup_file" GTK_THEME_NAME "$gtk_theme")"
    color_scheme="$(read_backup_value "$backup_file" COLOR_SCHEME "$color_scheme")"
    shell_theme="$(read_backup_value "$backup_file" USER_THEME_NAME "$shell_theme")"
    wm_theme="$(read_backup_value "$backup_file" WM_THEME_NAME "$wm_theme")"
    terminal_theme_variant="$(read_backup_value "$backup_file" TERMINAL_THEME_VARIANT "$terminal_theme_variant")"
    if backup_has_key "$backup_file" ACCENT_COLOR; then
      accent_color="$(read_backup_value "$backup_file" ACCENT_COLOR "'pink'")"
      restore_accent=1
    fi
    if backup_has_key "$backup_file" BACKGROUND_PICTURE_URI &&
      backup_has_key "$backup_file" BACKGROUND_PICTURE_URI_DARK; then
      background_picture_uri="$(read_backup_value "$backup_file" BACKGROUND_PICTURE_URI "''")"
      background_picture_uri_dark="$(read_backup_value "$backup_file" BACKGROUND_PICTURE_URI_DARK "''")"
      restore_background=1
    fi
  elif [ -f "$old_shell_backup" ]; then
    shell_theme="$(read_backup_value "$old_shell_backup" USER_THEME_NAME "$shell_theme")"
  fi

  run gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme"
  run gsettings set org.gnome.desktop.interface color-scheme "$color_scheme"
  if [ "$restore_accent" -eq 1 ]; then
    run gsettings set org.gnome.desktop.interface accent-color "$accent_color"
  fi
  if [ "$restore_background" -eq 1 ]; then
    run gsettings set org.gnome.desktop.background picture-uri "$background_picture_uri"
    run gsettings set org.gnome.desktop.background picture-uri-dark "$background_picture_uri_dark"
  fi
  run gsettings set org.gnome.shell.extensions.user-theme name "$shell_theme"
  run gsettings set org.gnome.desktop.wm.preferences theme "$wm_theme"
  run gsettings set org.gnome.Terminal.Legacy.Settings theme-variant "$terminal_theme_variant"
}

remove_repo_owned_theme_dir() {
  local target="$1"
  local marker="$2"

  [ -d "$target" ] || return 0

  if [ ! -f "$marker" ]; then
    log "Skipping $target because it is not marked as repo-owned."
    return 0
  fi

  run rm -rf "$target/gtk-3.0" "$target/gtk-4.0" "$target/gnome-shell" "$target/metacity-1"
  run rm -f "$target/index.theme" "$marker"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "+ remove empty theme directory $target, if empty"
  else
    rmdir "$target" 2>/dev/null || true
  fi
}

remove_theme_files() {
  remove_repo_owned_theme_dir "$THEME_TARGET" "$THEME_TARGET/$THEME_MARKER"
  remove_repo_owned_theme_dir "$LEGACY_THEME_TARGET" "$LEGACY_THEME_MARKER"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --keep-backup)
      KEEP_BACKUP=1
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
BACKUP_DIR="$TOOLS_DIR/desktop-color-backup"
THEME_NAME="kathrynwave"
THEME_MARKER=".kathrynwave"
THEME_TARGET="$HOME/.themes/$THEME_NAME"
LEGACY_THEME_TARGET="$HOME/.themes/${THEME_NAME%wave}-theme"
LEGACY_THEME_MARKER="$LEGACY_THEME_TARGET/.${THEME_NAME%wave}-theme"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$TOOLS_DIR"
fi

print_dry_run_manifest
restore_theme_settings
restore_gtk_user_css 3
restore_gtk_user_css 4
cleanup_legacy_gtk_import 3
cleanup_legacy_gtk_import 4
remove_theme_files

if [ "$KEEP_BACKUP" -eq 0 ] && [ -d "$BACKUP_DIR" ]; then
  run rm -rf "$BACKUP_DIR"
fi

log "kathrynwave desktop colors removed."
KATHRYNWAVE_EMBEDDED_UNINSTALL
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --keep-backup)
      KEEP_BACKUP=1
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

[ "$(id -u)" -ne 0 ] || die "do not run this uninstaller as root or with sudo"
[ -n "${HOME:-}" ] || die "HOME is not set"
command -v gsettings >/dev/null 2>&1 || die "gsettings is required"
command -v dconf >/dev/null 2>&1 || die "dconf is required"

find_layout

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$TOOLS_DIR"
fi

run_desktop_uninstaller
restore_terminal
remove_prompt

log "kathrynwave uninstalled."
