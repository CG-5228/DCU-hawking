#!/usr/bin/env bash
# Hawking CLI (shell edition): no Python required.
# Requires: bash, curl, jq; macOS Keychain (security) is optional on non-macOS.

set -u
set -o pipefail

VERSION='2026-08-13-shell.1'
API_BASE='https://hawking.computing.dcu.ie/api'
KEYCHAIN_SERVICE='ie.dcu.computing.hawking.shell'

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] %b\n' "$(stamp)" "$1"; }
err() { printf '%b%s%b\n' "$RED" "$1" "$RESET" >&2; }

usage() {
  cat <<'USAGE'
Usage: hawking [--version] [--forget-password] [FILE | DIRECTORY ...]

With no arguments, submit the newest recognized task file in the current folder.
When given a directory, submit its newest file matching a Hawking task.
You may also submit multiple explicit files at once.

Environment: HAWKING_USERNAME (or EINSTEIN_USERNAME, DCU_USERNAME, SOC_USERNAME)
USAGE
}

case "${1:-}" in
  -v|--version) printf 'hawking %s\n' "$VERSION"; exit 0 ;;
  -h|--help) usage; exit 0 ;;
esac

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Missing dependency: $cmd"
    [[ "$cmd" == jq ]] && err 'On a Mac with Homebrew, run: brew install jq'
    exit 1
  fi
done

username="${HAWKING_USERNAME:-${EINSTEIN_USERNAME:-${DCU_USERNAME:-${SOC_USERNAME:-$(id -un)}}}}"
if [[ -z "$username" ]]; then
  err 'No School of Computing username set. Export HAWKING_USERNAME first.'
  exit 1
fi
case "$username" in
  socexam|socguest|exam)
    err "Shared account '$username' cannot submit Hawking tasks."
    exit 1 ;;
esac

if [[ "${1:-}" == '--forget-password' ]]; then
  if command -v security >/dev/null 2>&1; then
    if security delete-generic-password -a "$username" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
      printf 'Saved Hawking password cleared for %s.\n' "$username"
    else
      printf 'No saved Hawking password was found for %s.\n' "$username"
    fi
  else
    printf 'No macOS Keychain is available; this CLI does not store passwords on disk.\n'
  fi
  exit 0
fi

if [[ "${1:-}" == '--' ]]; then shift; fi
for arg in "$@"; do
  case "$arg" in
    -*) err "Unknown option: $arg"; usage >&2; exit 2 ;;
  esac
done

# The Python original encrypts with a key embedded in its source code.
# Instead, macOS credentials are stored securely in the login Keychain.
password=''
if command -v security >/dev/null 2>&1; then
  password="$(security find-generic-password -a "$username" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)" || password=''
  if [[ -z "$password" ]]; then
    printf 'Hawking user: %s\n' "$username"
    printf 'Save your School of Computing password in macOS Keychain:\n'
    # Passing -w without a value prompts safely without exposing it in process args.
    if ! security add-generic-password -a "$username" -s "$KEYCHAIN_SERVICE" -U -w; then
      err 'Unable to save password to macOS Keychain.'
      exit 1
    fi
    password="$(security find-generic-password -a "$username" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)" || password=''
  fi
fi

if [[ -z "$password" ]]; then
  printf 'Hawking user: %s\nSchool of Computing password: ' "$username" >&2
  IFS= read -r -s password || { printf '\n' >&2; err 'Password input cancelled.'; exit 1; }
  printf '\n' >&2
fi
if [[ -z "$password" || "$password" == *$'\n'* || "$password" == *$'\r'* ]]; then
  err 'Empty or unsupported password format.'
  exit 1
fi

# Escape values for curl's configuration format. Passing credentials over
# stdin prevents the password from appearing in `ps` process arguments.
curl_config_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}
auth_string="$(curl_config_escape "$username:$password")"

TMPDIR_HAWKING="$(mktemp -d "${TMPDIR:-/tmp}/hawking-cli.XXXXXXXX")" || exit 1
trap 'rm -rf -- "$TMPDIR_HAWKING"' EXIT
RESPONSE_PATH="$TMPDIR_HAWKING/response.json"
API_JSON=''
HTTP_CODE=''

# api_request METHOD URL [FILE]: fills API_JSON; returns nonzero on failure.
api_request() {
  local method="$1" url="$2" file="${3:-}" curl_status=0 error_message=''
  local -a curl_args
  curl_args=(-q --config - --basic --silent --show-error --connect-timeout 15 --max-time 180
    --output "$RESPONSE_PATH" --write-out '%{http_code}')
  if [[ "$method" == POST ]]; then
    curl_args+=(--form "file=@${file}")
  fi
  curl_args+=(--url "$url")

  HTTP_CODE="$(printf 'user = "%s"\n' "$auth_string" | curl "${curl_args[@]}")" || curl_status=$?
  if (( curl_status != 0 )); then
    err "Network request failed (curl exit code $curl_status): $url"
    return 1
  fi
  if [[ "$HTTP_CODE" != 200 ]]; then
    error_message="$(jq -r 'if type == "object" then (.error // .message // "") | tostring else "" end' "$RESPONSE_PATH" 2>/dev/null)"
    err "Hawking API HTTP $HTTP_CODE${error_message:+: $error_message}"
    return 1
  fi
  if ! jq -e . "$RESPONSE_PATH" >/dev/null 2>&1; then
    err 'Invalid JSON returned by Hawking API.'
    return 1
  fi
  error_message="$(jq -r 'if type == "object" then (.error // "") | tostring else "" end' "$RESPONSE_PATH")"
  if [[ -n "$error_message" ]]; then
    err "Hawking API error: $error_message"
    return 1
  fi
  API_JSON="$(cat "$RESPONSE_PATH")"
  return 0
}

is_task() {
  jq -e --arg name "$1" \
    'if type == "object" then has($name) elif type == "array" then index($name) != null else false end' \
    <<< "$tasks_json" >/dev/null 2>&1
}

urlencode() { jq -nr --arg value "$1" '$value | @uri'; }

start_time="$SECONDS"
if ! api_request GET "$API_BASE/auth"; then
  err 'Unable to authenticate. If your password changed, use: hawking --forget-password'
  exit 1
fi
auth_json="$API_JSON"
auth_user="$(jq -r '.user // empty' <<< "$auth_json")"
if [[ -z "$auth_user" ]]; then
  err 'Authentication reply has no username.'
  exit 1
fi
log "${BLUE}Authenticated as $auth_user${RESET}"
exam_course="$(jq -r '.exam // empty' <<< "$auth_json")"
if [[ -n "$exam_course" ]]; then
  if [[ "$(jq -r '.inExam // false' <<< "$auth_json")" == true ]]; then
    log "${YELLOW}You are in an exam for $exam_course${RESET}"
  else
    log "${YELLOW}You have an exam for $exam_course, but it is happening elsewhere!${RESET}"
  fi
fi

if ! api_request GET "$API_BASE/tasks"; then
  err 'Unable to fetch assigned tasks.'
  exit 1
fi
tasks_json="$API_JSON"
if ! jq -e 'type == "array" or type == "object"' <<< "$tasks_json" >/dev/null; then
  err 'Unexpected format for assigned tasks.'
  exit 1
fi
task_count="$(jq 'length' <<< "$tasks_json")"
if [[ -n "$exam_course" ]]; then
  log "${GREEN}Fetched $task_count task(s) for $exam_course.${RESET}"
else
  log "${GREEN}Fetched $task_count task(s) for your module(s).${RESET}"
fi

if (( $# == 0 )); then set -- .; fi
shopt -s nullglob dotglob
files_to_submit=()
for input in "$@"; do
  if [[ -d "$input" ]]; then
    latest_file=''
    latest_time=-1
    for candidate in "$input"/*; do
      [[ -f "$candidate" ]] || continue
      candidate_name="${candidate##*/}"
      is_task "$candidate_name" || continue
      if [[ "$(uname -s)" == Darwin ]]; then
        candidate_time="$(stat -f '%m' "$candidate" 2>/dev/null)" || continue
      else
        candidate_time="$(stat -c '%Y' "$candidate" 2>/dev/null)" || continue
      fi
      if (( candidate_time > latest_time )); then
        latest_file="$candidate"
        latest_time="$candidate_time"
      fi
    done
    [[ -z "$latest_file" ]] || files_to_submit+=("$latest_file")
  else
    files_to_submit+=("$input")
  fi
done

attempted=0
exit_code=0
for file in "${files_to_submit[@]}"; do
  name="${file##*/}"
  if ! [[ -f "$file" ]]; then
    err "File not found: $file"
    exit_code=1
    continue
  fi
  if ! is_task "$name"; then
    log "${YELLOW}You do not have a task named $name.${RESET}"
    exit_code=1
    continue
  fi
  attempted=1
  log "Checking for task $name..."
  encoded_name="$(urlencode "$name")"
  if ! api_request GET "$API_BASE/moduleForTask/$encoded_name"; then
    err "Failed to fetch modules for $name."
    exit_code=1
    continue
  fi
  modules_json="$API_JSON"
  if ! jq -e 'type == "array"' <<< "$modules_json" >/dev/null; then
    err "Unexpected module data for $name."
    exit_code=1
    continue
  fi
  module_count="$(jq 'length' <<< "$modules_json")"
  if (( module_count == 0 )); then
    log "${YELLOW}No module found for task $name.${RESET}"
    exit_code=1
    continue
  fi

  module_index=0
  if (( module_count > 1 )); then
    log "There are $module_count modules with a task named $name. Choose a module:"
    for (( i=0; i<module_count; i++ )); do
      label="$(jq -r --argjson i "$i" '.[$i] | if (.banner // "") != "" then (.banner + (if (.legacy // "") != "" then " (" + .legacy + ")" else "" end)) else (.legacy // "Unknown module") end' <<< "$modules_json")"
      printf '  [%d] %s\n' "$((i+1))" "$label"
    done
    while :; do
      printf 'Module #? '
      IFS= read -r selected || { err 'Module selection cancelled.'; exit 1; }
      if [[ "$selected" =~ ^[0-9]+$ ]]; then
        selected_num=$((10#$selected))
        if (( selected_num >= 1 && selected_num <= module_count )); then
          module_index=$((selected_num - 1))
          break
        fi
      fi
      err 'Invalid module number; please choose again.'
    done
  fi

  module_info="$(jq -c --argjson i "$module_index" '.[$i]' <<< "$modules_json")"
  module_id="$(jq -r 'if (.banner // "") != "" then .banner else (.legacy // "") end' <<< "$module_info")"
  module_upload_id="$(jq -r '.id // empty | tostring' <<< "$module_info")"
  if [[ -z "$module_id" || -z "$module_upload_id" ]]; then
    err "Missing module ID for $name."
    exit_code=1
    continue
  fi
  module_label="$(printf '%s' "$module_id" | tr '[:lower:]' '[:upper:]')"
  log "Uploading $name for $module_label"
  if ! api_request POST "$API_BASE/upload/$module_upload_id/$encoded_name" "$file"; then
    err "*** Error uploading $name"
    exit_code=1
    continue
  fi
  upload_json="$API_JSON"
  if ! jq -e '.output.attempt != null' <<< "$upload_json" >/dev/null 2>&1; then
    err 'Unexpected upload response (missing attempt information).'
    exit_code=1
    continue
  fi
  submission_error="$(jq -r '.output.attempt.submissionError // empty | tostring' <<< "$upload_json")"
  attempt_id="$(jq -r '.output.attempt.id // empty | tostring' <<< "$upload_json")"
  if [[ -n "$submission_error" ]]; then
    log "${RED}*** failed: error submitting to runner ($submission_error)${RESET}"
    exit_code=2
  else
    if ! jq -e '.output.results | type == "array"' <<< "$upload_json" >/dev/null 2>&1; then
      err 'Unexpected upload response (missing test results).'
      exit_code=1
      continue
    fi
    total="$(jq '.output.results | length' <<< "$upload_json")"
    passed=0
    failed=0
    for (( i=0; i<total; i++ )); do
      if [[ "$(jq -r --argjson i "$i" '.output.results[$i].correct // false' <<< "$upload_json")" == true ]]; then
        log "${GREEN}*** test $((i+1)) ${BOLD}passed${RESET}"
        passed=$((passed+1))
      else
        log "${RED}*** test $((i+1)) ${BOLD}failed${RESET}"
        failed=$((failed+1))
      fi
    done
    printf '\n'
    (( failed == 0 )) || log "${RED}*** failed: $failed of $total${RESET}"
    (( passed == 0 )) || log "${GREEN}*** passed: $passed of $total${RESET}"
    if (( failed > 0 )); then
      log "${RED}*** overall: incorrect${RESET}"
      (( exit_code > 0 )) || exit_code=1
    else
      log "${GREEN}*** overall: correct${RESET}"
    fi
  fi
  printf '\n'
  if [[ -n "$attempt_id" ]]; then
    log "${BLUE}*** report: http://hawking.local/hawking/$module_id/result/$attempt_id${RESET}"
  fi
done

if (( attempted == 0 )); then
  err 'No task files found to upload.'
  exit_code=1
fi
log "Running took $((SECONDS - start_time)) seconds"
exit "$exit_code"
