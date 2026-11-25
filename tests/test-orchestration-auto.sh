#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GET_QUOTAS="$REPO_ROOT/orca-superpowers-orchestration-auto/scripts/get-quotas.sh"
AGENTS_FIXTURE="$REPO_ROOT/tests/fixtures/agent-installed.json"
ACCOUNTS_FIXTURE="$REPO_ROOT/tests/fixtures/account-list.json"

PASS=0
FAIL=0

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$name" "$expected" "$actual" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s (missing=%s)\n' "$name" "$needle" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    printf 'FAIL: %s (unexpected=%s)\n' "$name" "$needle" >&2
    FAIL=$((FAIL + 1))
  else
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  fi
}

run_collector_fixture() {
  bash "$GET_QUOTAS" --agents-file "$AGENTS_FIXTURE" --accounts-file "$ACCOUNTS_FIXTURE"
}

test_script_exists_and_bash_syntax() {
  if [ -f "$GET_QUOTAS" ] && bash -n "$GET_QUOTAS" 2>/dev/null; then
    printf 'PASS: test_script_exists_and_bash_syntax\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL: test_script_exists_and_bash_syntax (missing or syntax error: %s)\n' "$GET_QUOTAS" >&2
    FAIL=$((FAIL + 1))
  fi
}

test_no_forbidden_runtimes_in_script() {
  if [ ! -f "$GET_QUOTAS" ]; then
    printf 'FAIL: test_no_forbidden_runtimes_in_script (file missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local content
  content="$(cat "$GET_QUOTAS")"
  if printf '%s\n' "$content" | grep -E -q '(^|[^a-zA-Z0-9_-])(python3?|node|jq|pwsh|powershell)([^a-zA-Z0-9_-]|$)'; then
    printf 'FAIL: test_no_forbidden_runtimes_in_script (forbidden runtime found)\n' >&2
    FAIL=$((FAIL + 1))
  else
    printf 'PASS: test_no_forbidden_runtimes_in_script\n'
    PASS=$((PASS + 1))
  fi
}

test_installed_agents_extracted() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "installed_source_orca" "SOURCE|orca" "$out"
  assert_contains "installed_claude_default" "INSTALLED|claude|default" "$out"
  assert_contains "installed_codex" "INSTALLED|codex|" "$out"
  assert_contains "installed_opencode" "INSTALLED|opencode|" "$out"
  assert_contains "installed_opencode2" "INSTALLED|opencode2|" "$out"
  assert_contains "installed_antigravity" "INSTALLED|antigravity|" "$out"
  assert_contains "installed_copilot" "INSTALLED|copilot|" "$out"
}

test_claude_5h_and_weekly() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "claude_5h_and_weekly" "QUOTA|claude|ok|5|66|weekly|66|pro" "$out"
}

test_codex_5h_and_weekly() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "codex_5h_and_weekly" "QUOTA|codex|ok|0|74|weekly|74|plus" "$out"
}

test_antigravity_windows_and_buckets() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "antigravity_quota" "QUOTA|antigravity|ok|12|6|session|12|-" "$out"
  assert_contains "antigravity_bucket_gemini_weekly" "BUCKET|antigravity|Gemini Models|10080|6" "$out"
  assert_contains "antigravity_bucket_gemini_5h" "BUCKET|antigravity|Gemini Models|300|12" "$out"
  assert_contains "antigravity_bucket_claude_gpt_weekly" "BUCKET|antigravity|Claude and GPT models|10080|0" "$out"
  assert_contains "antigravity_bucket_claude_gpt_5h" "BUCKET|antigravity|Claude and GPT models|300|0" "$out"
}

test_unavailable_providers() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "unavailable_gemini" "QUOTA|gemini|unavailable|-|-|-|-|-" "$out"
  assert_contains "unavailable_kimi" "QUOTA|kimi|unavailable|-|-|-|-|-" "$out"
  assert_contains "unavailable_opencodeGo" "QUOTA|opencodeGo|unavailable|-|-|-|-|-" "$out"
}

test_no_pii_or_secrets() {
  local out combined
  out="$(run_collector_fixture 2>/dev/null || true)"
  combined="$(cat "$AGENTS_FIXTURE" "$ACCOUNTS_FIXTURE")
$out"
  assert_not_contains "no_pii_at" "@" "$combined"
  assert_not_contains "no_pii_org_uuid" "organizationUuid" "$combined"
  assert_not_contains "no_secret_bearer" "Bearer " "$combined"
  assert_not_contains "no_secret_access_token_snake" "access_token" "$combined"
  assert_not_contains "no_secret_access_token_camel" "accessToken" "$combined"
  assert_not_contains "no_secret_refresh_token" "refresh_token" "$combined"
  assert_not_contains "no_pii_win_users" 'C:\Users' "$combined"
}

test_script_exists_and_bash_syntax
test_no_forbidden_runtimes_in_script
test_installed_agents_extracted
test_claude_5h_and_weekly
test_codex_5h_and_weekly
test_antigravity_windows_and_buckets
test_unavailable_providers
test_no_pii_or_secrets

printf 'Summary: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
