#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_NAME="Eligibility Configuration Helper"
readonly ELIGIBILITY_DIR="${JAILBREAK_ELIGIBILITY_DIR:-/private/var/db/eligibilityd}"
readonly OS_ELIGIBILITY_DIR="${JAILBREAK_OS_ELIGIBILITY_DIR:-/private/var/db/os_eligibility}"
readonly ELIGIBILITY_PLIST="$ELIGIBILITY_DIR/eligibility.plist"
readonly OS_ELIGIBILITY_PLIST="$OS_ELIGIBILITY_DIR/eligibility.plist"
readonly PLISTBUDDY="${JAILBREAK_PLISTBUDDY:-/usr/libexec/PlistBuddy}"
readonly BACKUP_ROOT="${JAILBREAK_BACKUP_ROOT:-/private/var/db/eligibility-backups}"

CLEANUP_NEEDED=0
APPLIED_CHANGES=0

declare -a MANAGED_DIRS=(
  "$ELIGIBILITY_DIR"
  "$OS_ELIGIBILITY_DIR"
)

declare -a MANAGED_PLISTS=(
  "$ELIGIBILITY_PLIST"
  "$OS_ELIGIBILITY_PLIST"
)

declare -a CHANGES=(
  "Apple Clean Up|$OS_ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_STRONTIUM|Set :OS_ELIGIBILITY_DOMAIN_STRONTIUM:os_eligibility_answer_t 4"
  "Xcode Predictive Code Completion|$OS_ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_XCODE_LLM|Set :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:os_eligibility_answer_t 4"
  "Coding with Apple Intelligence in Xcode|$OS_ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST|Set :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:os_eligibility_answer_t 4"
  "Apple Intelligence|$ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_GREYMATTER|Set :OS_ELIGIBILITY_DOMAIN_GREYMATTER:os_eligibility_answer_t 4"
  "Apple Foundation Models|$ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS|Set :OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS:os_eligibility_answer_t 4"
)

if [[ -t 1 ]]; then
  readonly BOLD="$(tput bold 2>/dev/null || true)"
  readonly DIM="$(tput dim 2>/dev/null || true)"
  readonly RESET="$(tput sgr0 2>/dev/null || true)"
  readonly RED="$(tput setaf 1 2>/dev/null || true)"
  readonly GREEN="$(tput setaf 2 2>/dev/null || true)"
  readonly YELLOW="$(tput setaf 3 2>/dev/null || true)"
  readonly BLUE="$(tput setaf 4 2>/dev/null || true)"
else
  readonly BOLD=""
  readonly DIM=""
  readonly RESET=""
  readonly RED=""
  readonly GREEN=""
  readonly YELLOW=""
  readonly BLUE=""
fi

print_line() {
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'
}

banner() {
  clear 2>/dev/null || true
  print_line
  printf '%s%s%s\n' "$BOLD" "$SCRIPT_NAME" "$RESET"
  printf '%smacOS plist editor with access checks, backups, restore, and confirmations.%s\n' "$DIM" "$RESET"
  print_line
}

info() {
  printf '%s%s%s %s\n' "$BLUE" "*" "$RESET" "$1"
}

success() {
  printf '%s%s%s %s\n' "$GREEN" "OK" "$RESET" "$1"
}

warn() {
  printf '%s%s%s %s\n' "$YELLOW" "!" "$RESET" "$1"
}

fail() {
  printf '%s%s%s %s\n' "$RED" "ERR" "$RESET" "$1" >&2
}

die() {
  fail "$1"
  exit 1
}

cleanup() {
  local exit_code=$?

  trap - EXIT INT TERM

  if [[ "$CLEANUP_NEEDED" -eq 1 ]]; then
    printf '\n'
    warn "Cleaning up protected plist state before exit."
    sudo chmod 644 "${MANAGED_PLISTS[@]}" 2>/dev/null || true
    sudo chflags uchg "${MANAGED_PLISTS[@]}" 2>/dev/null || true
  fi

  exit "$exit_code"
}

confirm() {
  local prompt="$1"
  local reply

  while true; do
    printf '%s [y/N]: ' "$prompt"
    IFS= read -r reply || return 1
    case "$reply" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]|'') return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: ./jailbreak.sh <command> [argument]

Commands:
  help                 Show this help text.
  check                Verify macOS, required tools, SIP status, and plist directory access.
  status               Read current managed values from the plist files.
  apply                Back up plist files, then prompt before each PlistBuddy change.
  backups              List available backup directories.
  restore [latest|DIR] Restore plist files from a backup directory.
                       DIR can be a full path or a timestamp from the backups command.

Notes:
  - Terminal must have Full Disk Access for $OS_ELIGIBILITY_DIR.
  - Before apply or restore, boot into Recovery Mode and run: csrutil disable
  - Reboot after applying or restoring changes.
  - os_eligibility_answer_t values: 2 = ineligible, 4 = eligible.
EOF
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This script is intended to run on macOS only."
}

require_tools() {
  [[ -x "$PLISTBUDDY" ]] || die "PlistBuddy was not found at $PLISTBUDDY."
  command -v csrutil >/dev/null 2>&1 || die "csrutil was not found. Run this on macOS."
  command -v sudo >/dev/null 2>&1 || die "sudo is required."
}

get_sip_status() {
  csrutil status 2>/dev/null || true
}

require_sip_disabled() {
  local sip_status

  info "Before running this command, boot into Recovery Mode and run: csrutil disable"
  info "After returning to macOS, run this script again. Re-enable SIP when you are done if appropriate."
  printf '\n'

  sip_status="$(get_sip_status)"
  printf '%sSIP status:%s %s\n' "$BOLD" "$RESET" "${sip_status:-unable to read}"

  if [[ "$sip_status" != *"System Integrity Protection status: disabled."* ]]; then
    die "System Integrity Protection is not disabled. Stop here, use Recovery Mode, and run csrutil disable."
  fi

  success "SIP is disabled."
}

check_directory_access() {
  local dir="$1"

  [[ -d "$dir" ]] || return 1
  [[ -r "$dir" && -x "$dir" ]] || return 1
  ls "$dir" >/dev/null 2>&1
}

require_full_disk_access() {
  local dir
  local failed=0

  for dir in "${MANAGED_DIRS[@]}"; do
    if check_directory_access "$dir"; then
      success "Directory is accessible: $dir"
    else
      failed=1
      fail "Cannot access $dir"
    fi
  done

  if [[ "$failed" -ne 0 ]]; then
    die "Grant Terminal Full Disk Access in System Settings, then run this command again."
  fi
}

require_plists() {
  local plist

  for plist in "${MANAGED_PLISTS[@]}"; do
    [[ -f "$plist" ]] || die "Required plist was not found: $plist"
    sudo test -r "$plist" || die "Required plist is not readable: $plist"
    sudo "$PLISTBUDDY" -c "Print" "$plist" >/dev/null || die "Plist validation failed: $plist"
  done

  success "Required plist files are present and valid."
}

prime_sudo() {
  info "Requesting administrator access once for protected system files."
  sudo -v || die "Administrator authorization failed."
  success "Administrator access confirmed."
}

backup_plists() {
  local timestamp backup_dir plist backup_file

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  backup_dir="$BACKUP_ROOT/$timestamp"

  info "Creating backups before any PlistBuddy changes."
  sudo mkdir -p "$backup_dir"

  for plist in "${MANAGED_PLISTS[@]}"; do
    backup_file="$backup_dir/$(basename "$(dirname "$plist")")-$(basename "$plist")"
    sudo cp -p "$plist" "$backup_file"
    success "Backed up $plist to $backup_file"
  done
}

unlock_plists() {
  info "Temporarily clearing immutable flags so protected files can be updated."
  sudo chflags nouchg "${MANAGED_PLISTS[@]}"
  CLEANUP_NEEDED=1
  success "Protected flags cleared for this session."
}

lock_down_plists() {
  info "Restoring conservative permissions and immutable flags."
  sudo chmod 644 "${MANAGED_PLISTS[@]}"
  sudo chflags uchg "${MANAGED_PLISTS[@]}"
  CLEANUP_NEEDED=0
  success "Permissions set to 644 and immutable flags restored."
}

eligibility_meaning() {
  local value="$1"

  case "$value" in
    2) printf 'ineligible' ;;
    4) printf 'eligible' ;;
    missing) printf 'missing' ;;
    *) printf 'unknown' ;;
  esac
}

print_managed_status() {
  local change label plist domain command value meaning

  print_line
  printf '%sCurrent managed plist values%s\n' "$BOLD" "$RESET"
  printf 'os_eligibility_answer_t: 2 = ineligible, 4 = eligible\n'
  print_line

  for change in "${CHANGES[@]}"; do
    IFS='|' read -r label plist domain command <<< "$change"
    value="$(sudo "$PLISTBUDDY" -c "Print :$domain:os_eligibility_answer_t" "$plist" 2>/dev/null || printf 'missing')"
    meaning="$(eligibility_meaning "$value")"
    printf '%s\n' "$label"
    printf '  plist:  %s\n' "$plist"
    printf '  key:    %s:os_eligibility_answer_t\n' "$domain"
    printf '  value:  %s (%s)\n' "$value" "$meaning"
  done
}

run_plistbuddy_change() {
  local label="$1"
  local plist="$2"
  local command="$3"

  printf '\n'
  print_line
  printf '%s%s%s\n' "$BOLD" "$label" "$RESET"
  printf '%sTarget:%s  %s\n' "$DIM" "$RESET" "$plist"
  printf '%sCommand:%s %s\n' "$DIM" "$RESET" "$command"

  if confirm "Run this PlistBuddy command?"; then
    sudo "$PLISTBUDDY" -c "$command" "$plist"
    APPLIED_CHANGES=$((APPLIED_CHANGES + 1))
    success "Applied: $label"
  else
    warn "Skipped: $label"
  fi
}

apply_changes() {
  local change label plist domain command

  for change in "${CHANGES[@]}"; do
    IFS='|' read -r label plist domain command <<< "$change"
    run_plistbuddy_change "$label" "$plist" "$command"
  done
}

show_apply_summary() {
  printf '\n'
  print_line
  success "Finished processing requested plist changes."
  if [[ "$APPLIED_CHANGES" -gt 0 ]]; then
    warn "A reboot is required before these changes can take effect."
  else
    info "No PlistBuddy changes were applied, so no reboot is required by this script."
  fi
  info "Keep the backup directory until you have verified the system behaves as expected."
  print_line
}

list_backups() {
  local found=0
  local backup

  print_line
  printf '%sAvailable backups%s\n' "$BOLD" "$RESET"
  print_line

  if [[ ! -d "$BACKUP_ROOT" ]]; then
    warn "No backup root exists yet: $BACKUP_ROOT"
    return 0
  fi

  while IFS= read -r backup; do
    found=1
    printf '%s\n' "$backup"
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r)

  [[ "$found" -eq 1 ]] || warn "No backups found in $BACKUP_ROOT"
}

latest_backup_dir() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n 1
}

resolve_backup_dir() {
  local requested="$1"

  if [[ "$requested" == "latest" ]]; then
    latest_backup_dir
  elif [[ -d "$requested" ]]; then
    printf '%s\n' "$requested"
  else
    printf '%s\n' "$BACKUP_ROOT/$requested"
  fi
}

require_backup_files() {
  local backup_dir="$1"

  [[ -d "$backup_dir" ]] || die "Backup directory was not found: $backup_dir"
  [[ -f "$backup_dir/eligibilityd-eligibility.plist" ]] || die "Missing backup file: $backup_dir/eligibilityd-eligibility.plist"
  [[ -f "$backup_dir/os_eligibility-eligibility.plist" ]] || die "Missing backup file: $backup_dir/os_eligibility-eligibility.plist"
}

restore_backup() {
  local requested="${1:-latest}"
  local backup_dir

  backup_dir="$(resolve_backup_dir "$requested")"
  [[ -n "$backup_dir" ]] || die "No backups are available in $BACKUP_ROOT"

  require_backup_files "$backup_dir"

  printf '\n'
  print_line
  printf '%sRestore plist files%s\n' "$BOLD" "$RESET"
  printf '%sBackup:%s %s\n' "$DIM" "$RESET" "$backup_dir"
  print_line

  confirm "Restore both managed plist files from this backup?" || die "Restore cancelled."

  backup_plists
  unlock_plists
  sudo cp -p "$backup_dir/eligibilityd-eligibility.plist" "$ELIGIBILITY_PLIST"
  sudo cp -p "$backup_dir/os_eligibility-eligibility.plist" "$OS_ELIGIBILITY_PLIST"
  lock_down_plists

  success "Restored plist files from $backup_dir"
  warn "A reboot is required before restored values can take effect."
}

cmd_check() {
  banner
  require_macos
  require_tools

  printf '%sSIP status:%s %s\n' "$BOLD" "$RESET" "$(get_sip_status)"
  require_full_disk_access
  prime_sudo
  require_plists
}

cmd_status() {
  banner
  require_macos
  require_tools
  require_full_disk_access
  prime_sudo
  require_plists
  print_managed_status
}

cmd_apply() {
  banner
  require_macos
  require_tools
  require_full_disk_access
  require_sip_disabled
  prime_sudo
  require_plists
  backup_plists
  unlock_plists
  apply_changes
  lock_down_plists
  show_apply_summary
}

cmd_backups() {
  banner
  require_macos
  list_backups
}

cmd_restore() {
  banner
  require_macos
  require_tools
  require_full_disk_access
  require_sip_disabled
  prime_sudo
  require_plists
  restore_backup "${1:-latest}"
}

main() {
  local command="${1:-help}"
  shift || true

  trap cleanup EXIT INT TERM

  case "$command" in
    help|-h|--help) usage ;;
    check) cmd_check ;;
    status) cmd_status ;;
    apply) cmd_apply ;;
    backups) cmd_backups ;;
    restore) cmd_restore "$@" ;;
    *)
      usage
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"
