#!/usr/bin/env bash
# tests/test-status-matrix.sh - Force status matrix across quiet/verbose profiles

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${PROJECT_DIR}/lib"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; [[ -n "${2:-}" ]] && echo "  expected: $2" && echo "  got:      $3"; }
assert_eq() {
	local label="$1" expected="$2" actual="$3"
	if [[ "${expected}" == "${actual}" ]]; then pass "${label}"; else fail "${label}" "${expected}" "${actual}"; fi
}

TMP_DIR="$(mktemp -d /tmp/ccp_status_matrix_XXXXXX)"
STATUS_FILE="${TMP_DIR}/status.txt"
CONTEXT_FILE="${TMP_DIR}/context.txt"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

run_event() {
	local profile="$1"
	local event_name="$2"
	local payload="$3"
	printf 'BASE' > "${STATUS_FILE}"
	printf '%s' "${payload}" \
		| CCP_STATUS_FILE="${STATUS_FILE}" CCP_CONTEXT_FILE="${CONTEXT_FILE}" CCP_STATUS_PROFILE="${profile}" \
		  bash "${LIB_DIR}/hook_runner.sh" event "${event_name}" >/dev/null 2>&1 || true
	cat "${STATUS_FILE}" 2>/dev/null || true
}

echo ""
echo "═══ status matrix: quiet profile ═══"
assert_eq "quiet PermissionRequest" "⏸️ Awaiting approval" "$(run_event quiet PermissionRequest '{}')"
assert_eq "quiet Notification action-needed" "🙋 Input needed" \
	"$(run_event quiet Notification '{"message":"Action required: choose one option"}')"
assert_eq "quiet Notification generic suppressed" "BASE" \
	"$(run_event quiet Notification '{"message":"Background refresh complete"}')"
assert_eq "quiet TaskCompleted" "🏁 Completed" "$(run_event quiet TaskCompleted '{}')"
assert_eq "quiet SessionEnd clear" "🏁 Completed" "$(run_event quiet SessionEnd '{"reason":"clear"}')"
assert_eq "quiet SessionEnd compact" "🏁 Completed" "$(run_event quiet SessionEnd '{"reason":"compact"}')"
assert_eq "quiet SessionEnd logout" "🏁 Completed" "$(run_event quiet SessionEnd '{"reason":"logout"}')"
assert_eq "quiet SessionEnd bypass permissions disabled" "🏁 Completed" \
	"$(run_event quiet SessionEnd '{"reason":"bypass_permissions_disabled"}')"
assert_eq "quiet SessionStart suppressed" "BASE" "$(run_event quiet SessionStart '{}')"
assert_eq "quiet PreCompact suppressed" "BASE" "$(run_event quiet PreCompact '{}')"
assert_eq "quiet SubagentStart suppressed" "BASE" "$(run_event quiet SubagentStart '{}')"
assert_eq "quiet SubagentStop suppressed" "BASE" "$(run_event quiet SubagentStop '{}')"
assert_eq "quiet TeammateIdle suppressed" "BASE" "$(run_event quiet TeammateIdle '{}')"
assert_eq "quiet ConfigChange suppressed" "BASE" "$(run_event quiet ConfigChange '{}')"
assert_eq "quiet WorktreeCreate suppressed" "BASE" "$(run_event quiet WorktreeCreate '{}')"
assert_eq "quiet WorktreeRemove suppressed" "BASE" "$(run_event quiet WorktreeRemove '{}')"
assert_eq "quiet unknown event suppressed" "BASE" "$(run_event quiet UnknownFutureEvent '{}')"

echo ""
echo "═══ status matrix: verbose profile ═══"
assert_eq "verbose PermissionRequest" "⏸️ Awaiting approval" "$(run_event verbose PermissionRequest '{}')"
assert_eq "verbose Notification action-needed" "🙋 Input needed" \
	"$(run_event verbose Notification '{"message":"Needs your input now"}')"
assert_eq "verbose Notification generic" "🔔 Notification" \
	"$(run_event verbose Notification '{"message":"Background refresh complete"}')"
assert_eq "verbose TaskCompleted" "🏁 Completed" "$(run_event verbose TaskCompleted '{}')"
assert_eq "verbose SessionEnd clear" "🏁 Completed" "$(run_event verbose SessionEnd '{"reason":"clear"}')"
assert_eq "verbose SessionEnd generic reason" "🔔 Session ended" "$(run_event verbose SessionEnd '{"reason":"manual"}')"
assert_eq "verbose SessionStart" "🚀 Session started" "$(run_event verbose SessionStart '{}')"
assert_eq "verbose PreCompact" "🧠 Compacting" "$(run_event verbose PreCompact '{}')"
assert_eq "verbose SubagentStart" "🤖 Subagent started" "$(run_event verbose SubagentStart '{}')"
assert_eq "verbose SubagentStop" "✅ Subagent finished" "$(run_event verbose SubagentStop '{}')"
assert_eq "verbose TeammateIdle" "👥 Teammate idle" "$(run_event verbose TeammateIdle '{}')"
assert_eq "verbose ConfigChange" "⚙️ Config changed" "$(run_event verbose ConfigChange '{}')"
assert_eq "verbose WorktreeCreate fallback" "🔔 WorktreeCreate" "$(run_event verbose WorktreeCreate '{}')"
assert_eq "verbose WorktreeRemove fallback" "🔔 WorktreeRemove" "$(run_event verbose WorktreeRemove '{}')"
assert_eq "verbose unknown event fallback" "🔔 UnknownFutureEvent" "$(run_event verbose UnknownFutureEvent '{}')"

echo ""
echo "═══ status matrix results: ${PASS} passed, ${FAIL} failed ═══"
[[ "${FAIL}" -eq 0 ]] && exit 0 || exit 1
