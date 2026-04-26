#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_NAME="Eligibility 配置助手"
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
  "照片清理|$OS_ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_STRONTIUM|Set :OS_ELIGIBILITY_DOMAIN_STRONTIUM:os_eligibility_answer_t 4"
  "Xcode 预测式代码补全|$OS_ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_XCODE_LLM|Set :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:os_eligibility_answer_t 4"
  "Xcode 中的 Apple Intelligence 编码辅助|$OS_ELIGIBILITY_PLIST|OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST|Set :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:os_eligibility_answer_t 4"
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
  printf '%smacOS plist 编辑工具，包含访问检查、备份、恢复和确认流程。%s\n' "$DIM" "$RESET"
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
    warn "退出前正在清理受保护 plist 的状态。"
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
      *) warn "请输入 yes 或 no。" ;;
    esac
  done
}

usage() {
  cat <<EOF
用法: ./jailbreak_cn.sh <命令> [参数]

命令:
  help                 显示此帮助信息。
  check                检查 macOS、必要工具、SIP 状态和 plist 目录访问权限。
  status               从 plist 文件读取当前被管理的值。
  apply                先备份 plist 文件，再逐条确认 PlistBuddy 修改。
  backups              列出可用备份目录。
  restore [latest|DIR] 从备份目录恢复 plist 文件。
                       DIR 可以是完整路径，也可以是 backups 命令显示的时间戳。

说明:
  - Terminal 必须拥有 $OS_ELIGIBILITY_DIR 的完整磁盘访问权限。
  - 执行 apply 或 restore 前，请进入恢复模式并运行: csrutil disable
  - 应用或恢复变更后需要重启。
  - os_eligibility_answer_t: 2 = 不符合资格，4 = 符合资格。
EOF
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "此脚本只适用于 macOS。"
}

require_tools() {
  [[ -x "$PLISTBUDDY" ]] || die "未找到 PlistBuddy: $PLISTBUDDY"
  command -v csrutil >/dev/null 2>&1 || die "未找到 csrutil。请在 macOS 上运行。"
  command -v sudo >/dev/null 2>&1 || die "需要 sudo。"
}

get_sip_status() {
  csrutil status 2>/dev/null || true
}

require_sip_disabled() {
  local sip_status

  info "运行此命令前，请进入恢复模式并执行: csrutil disable"
  info "回到 macOS 后再次运行此脚本。完成后可按需重新启用 SIP。"
  printf '\n'

  sip_status="$(get_sip_status)"
  printf '%sSIP 状态:%s %s\n' "$BOLD" "$RESET" "${sip_status:-无法读取}"

  if [[ "$sip_status" != *"System Integrity Protection status: disabled."* ]]; then
    die "System Integrity Protection 尚未关闭。请先进入恢复模式运行 csrutil disable。"
  fi

  success "SIP 已关闭。"
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
      success "目录可访问: $dir"
    else
      failed=1
      fail "无法访问目录: $dir"
    fi
  done

  if [[ "$failed" -ne 0 ]]; then
    die "请在系统设置中授予 Terminal 完整磁盘访问权限，然后重试。"
  fi
}

require_plists() {
  local plist

  for plist in "${MANAGED_PLISTS[@]}"; do
    [[ -f "$plist" ]] || die "未找到必要的 plist: $plist"
    sudo test -r "$plist" || die "无法读取必要的 plist: $plist"
    sudo "$PLISTBUDDY" -c "Print" "$plist" >/dev/null || die "plist 校验失败: $plist"
  done

  success "必要的 plist 文件存在且有效。"
}

prime_sudo() {
  info "正在请求管理员权限以访问受保护的系统文件。"
  sudo -v || die "管理员授权失败。"
  success "管理员权限已确认。"
}

backup_plists() {
  local timestamp backup_dir plist backup_file

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  backup_dir="$BACKUP_ROOT/$timestamp"

  info "在执行任何 PlistBuddy 修改前创建备份。"
  sudo mkdir -p "$backup_dir"

  for plist in "${MANAGED_PLISTS[@]}"; do
    backup_file="$backup_dir/$(basename "$(dirname "$plist")")-$(basename "$plist")"
    sudo cp -p "$plist" "$backup_file"
    success "已备份 $plist 到 $backup_file"
  done
}

unlock_plists() {
  info "临时清除 immutable 标记，以便更新受保护文件。"
  sudo chflags nouchg "${MANAGED_PLISTS[@]}"
  CLEANUP_NEEDED=1
  success "本次会话已清除保护标记。"
}

lock_down_plists() {
  info "正在恢复保守权限和 immutable 标记。"
  sudo chmod 644 "${MANAGED_PLISTS[@]}"
  sudo chflags uchg "${MANAGED_PLISTS[@]}"
  CLEANUP_NEEDED=0
  success "权限已设置为 644，immutable 标记已恢复。"
}

eligibility_meaning() {
  local value="$1"

  case "$value" in
    2) printf '不符合资格' ;;
    4) printf '符合资格' ;;
    missing) printf '缺失' ;;
    *) printf '未知' ;;
  esac
}

print_managed_status() {
  local change label plist domain command value meaning

  print_line
  printf '%s当前被管理的 plist 值%s\n' "$BOLD" "$RESET"
  printf 'os_eligibility_answer_t: 2 = 不符合资格，4 = 符合资格\n'
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
  printf '%s目标:%s  %s\n' "$DIM" "$RESET" "$plist"
  printf '%s命令:%s %s\n' "$DIM" "$RESET" "$command"

  if confirm "是否运行这条 PlistBuddy 命令？"; then
    sudo "$PLISTBUDDY" -c "$command" "$plist"
    APPLIED_CHANGES=$((APPLIED_CHANGES + 1))
    success "已应用: $label"
  else
    warn "已跳过: $label"
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
  success "已完成请求的 plist 变更处理。"
  if [[ "$APPLIED_CHANGES" -gt 0 ]]; then
    warn "需要重启后变更才会生效。"
  else
    info "未应用任何 PlistBuddy 变更，因此此脚本不要求重启。"
  fi
  info "确认系统行为正常前，请保留备份目录。"
  print_line
}

list_backups() {
  local found=0
  local backup

  print_line
  printf '%s可用备份%s\n' "$BOLD" "$RESET"
  print_line

  if [[ ! -d "$BACKUP_ROOT" ]]; then
    warn "备份根目录尚不存在: $BACKUP_ROOT"
    return 0
  fi

  while IFS= read -r backup; do
    found=1
    printf '%s\n' "$backup"
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r)

  [[ "$found" -eq 1 ]] || warn "在 $BACKUP_ROOT 中没有找到备份"
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

  [[ -d "$backup_dir" ]] || die "未找到备份目录: $backup_dir"
  [[ -f "$backup_dir/eligibilityd-eligibility.plist" ]] || die "缺少备份文件: $backup_dir/eligibilityd-eligibility.plist"
  [[ -f "$backup_dir/os_eligibility-eligibility.plist" ]] || die "缺少备份文件: $backup_dir/os_eligibility-eligibility.plist"
}

restore_backup() {
  local requested="${1:-latest}"
  local backup_dir

  backup_dir="$(resolve_backup_dir "$requested")"
  [[ -n "$backup_dir" ]] || die "在 $BACKUP_ROOT 中没有可用备份"

  require_backup_files "$backup_dir"

  printf '\n'
  print_line
  printf '%s恢复 plist 文件%s\n' "$BOLD" "$RESET"
  printf '%s备份:%s %s\n' "$DIM" "$RESET" "$backup_dir"
  print_line

  confirm "是否从此备份恢复两个被管理的 plist 文件？" || die "恢复已取消。"

  backup_plists
  unlock_plists
  sudo cp -p "$backup_dir/eligibilityd-eligibility.plist" "$ELIGIBILITY_PLIST"
  sudo cp -p "$backup_dir/os_eligibility-eligibility.plist" "$OS_ELIGIBILITY_PLIST"
  lock_down_plists

  success "已从 $backup_dir 恢复 plist 文件"
  warn "需要重启后恢复的值才会生效。"
}

cmd_check() {
  banner
  require_macos
  require_tools

  printf '%sSIP 状态:%s %s\n' "$BOLD" "$RESET" "$(get_sip_status)"
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
      die "未知命令: $command"
      ;;
  esac
}

main "$@"
