#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT="$ROOT_DIR/jailbreak.sh"

TMP_DIR=""
TESTS_RUN=0
TESTS_FAILED=0

pass() {
  printf 'ok - %s\n' "$1"
}

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local name="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail_test "$name"
    printf 'Expected to find: %s\n' "$needle" >&2
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local name="$3"

  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail_test "$name"
    printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual" >&2
  fi
}

run_test() {
  local name="$1"
  shift

  TESTS_RUN=$((TESTS_RUN + 1))
  "$@" || fail_test "$name"
}

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

write_stub_commands() {
  local bin_dir="$1"

  cat > "$bin_dir/uname" <<'STUB'
#!/usr/bin/env bash
printf 'Darwin\n'
STUB

  cat > "$bin_dir/csrutil" <<'STUB'
#!/usr/bin/env bash
if [[ "${SIP_STATUS:-disabled}" == "disabled" ]]; then
  printf 'System Integrity Protection status: disabled.\n'
else
  printf 'System Integrity Protection status: enabled.\n'
fi
STUB

  cat > "$bin_dir/sudo" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "-v" ]]; then
  exit 0
fi
exec "$@"
STUB

  cat > "$bin_dir/chflags" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

  chmod +x "$bin_dir/uname" "$bin_dir/csrutil" "$bin_dir/sudo" "$bin_dir/chflags"
}

write_plistbuddy_stub() {
  local path="$1"

  cat > "$path" <<'STUB'
#!/usr/bin/env bash
command=""
file=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -c)
      command="$2"
      shift 2
      ;;
    *)
      file="$1"
      shift
      ;;
  esac
done

case "$command" in
  Print)
    [[ -f "$file" ]] || exit 1
    printf 'fake plist\n'
    ;;
  "Print :OS_ELIGIBILITY_DOMAIN_STRONTIUM:os_eligibility_answer_t")
    printf '2\n'
    ;;
  "Print :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:os_eligibility_answer_t")
    printf '4\n'
    ;;
  "Print :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:os_eligibility_answer_t")
    exit 1
    ;;
  "Print :OS_ELIGIBILITY_DOMAIN_GREYMATTER:os_eligibility_answer_t")
    printf '2\n'
    ;;
  "Print :OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS:os_eligibility_answer_t")
    printf '4\n'
    ;;
  Set*)
    printf '%s\n' "$command" >> "${PLISTBUDDY_SET_LOG:?}"
    ;;
  *)
    printf 'unsupported command: %s\n' "$command" >&2
    exit 1
    ;;
esac
STUB

  chmod +x "$path"
}

setup_fixture() {
  TMP_DIR="$(mktemp -d)"
  mkdir -p "$TMP_DIR/bin" "$TMP_DIR/eligibilityd" "$TMP_DIR/os_eligibility" "$TMP_DIR/backups"
  printf 'active eligibility\n' > "$TMP_DIR/eligibilityd/eligibility.plist"
  printf 'active os eligibility\n' > "$TMP_DIR/os_eligibility/eligibility.plist"
  write_stub_commands "$TMP_DIR/bin"
  write_plistbuddy_stub "$TMP_DIR/PlistBuddy"

  export PATH="$TMP_DIR/bin:$PATH"
  export JAILBREAK_ELIGIBILITY_DIR="$TMP_DIR/eligibilityd"
  export JAILBREAK_OS_ELIGIBILITY_DIR="$TMP_DIR/os_eligibility"
  export JAILBREAK_BACKUP_ROOT="$TMP_DIR/backups"
  export JAILBREAK_PLISTBUDDY="$TMP_DIR/PlistBuddy"
  export PLISTBUDDY_SET_LOG="$TMP_DIR/plistbuddy-set.log"
  export TERM=dumb
}

run_script() {
  bash "$SCRIPT" "$@" 2>&1
}

test_help_lists_commands_and_meanings() {
  local output
  output="$(run_script help)"

  assert_contains "$output" "check" "help lists check"
  assert_contains "$output" "status" "help lists status"
  assert_contains "$output" "restore [latest|DIR]" "help lists restore"
  assert_contains "$output" "2 = ineligible, 4 = eligible" "help explains plist values"
}

test_status_decodes_values() {
  local output
  output="$(run_script status)"

  assert_contains "$output" "Apple Clean Up" "status shows managed label"
  assert_contains "$output" "value:  2 (ineligible)" "status decodes ineligible"
  assert_contains "$output" "value:  4 (eligible)" "status decodes eligible"
  assert_contains "$output" "value:  missing (missing)" "status decodes missing"
}

test_apply_requires_disabled_sip() {
  local output

  set +e
  output="$(SIP_STATUS=enabled run_script apply)"
  local status=$?
  set -e

  assert_equals "1" "$status" "apply exits when SIP is enabled"
  assert_contains "$output" "System Integrity Protection is not disabled" "apply explains SIP failure"
}

test_apply_can_skip_all_commands() {
  local output
  output="$(printf 'n\nn\nn\nn\nn\n' | run_script apply)"

  assert_contains "$output" "Creating backups before any PlistBuddy changes." "apply creates backups first"
  assert_contains "$output" "Skipped: Apple Clean Up" "apply can skip individual command"
  assert_contains "$output" "No PlistBuddy changes were applied" "apply reports no-op"
}

test_backups_lists_directories() {
  local output
  mkdir -p "$JAILBREAK_BACKUP_ROOT/20260101-010101" "$JAILBREAK_BACKUP_ROOT/20260102-010101"

  output="$(run_script backups)"

  assert_contains "$output" "$JAILBREAK_BACKUP_ROOT/20260102-010101" "backups lists newest directory"
  assert_contains "$output" "$JAILBREAK_BACKUP_ROOT/20260101-010101" "backups lists older directory"
}

test_restore_latest_backup() {
  local backup_dir="$JAILBREAK_BACKUP_ROOT/20260103-030303"
  local eligibility_content os_content

  mkdir -p "$backup_dir"
  printf 'restored eligibility\n' > "$backup_dir/eligibilityd-eligibility.plist"
  printf 'restored os eligibility\n' > "$backup_dir/os_eligibility-eligibility.plist"

  printf 'y\n' | run_script restore "$backup_dir" >/dev/null

  eligibility_content="$(cat "$JAILBREAK_ELIGIBILITY_DIR/eligibility.plist")"
  os_content="$(cat "$JAILBREAK_OS_ELIGIBILITY_DIR/eligibility.plist")"

  assert_equals "restored eligibility" "$eligibility_content" "restore replaces eligibility plist"
  assert_equals "restored os eligibility" "$os_content" "restore replaces os eligibility plist"
}

main() {
  trap cleanup EXIT
  setup_fixture

  run_test "help lists commands and meanings" test_help_lists_commands_and_meanings
  run_test "status decodes values" test_status_decodes_values
  run_test "apply requires disabled SIP" test_apply_requires_disabled_sip
  run_test "apply can skip all commands" test_apply_can_skip_all_commands
  run_test "backups lists directories" test_backups_lists_directories
  run_test "restore latest backup" test_restore_latest_backup

  printf '\n%d tests run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
