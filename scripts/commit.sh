#!/bin/bash
set -euo pipefail

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Helpers ───
info()  { echo -e "${CYAN}${BOLD}→${RESET} $1"; }
ok()    { echo -e "${GREEN}${BOLD}✔${RESET} $1"; }
warn()  { echo -e "${YELLOW}${BOLD}⚠${RESET} $1"; }
fail()  { echo -e "${RED}${BOLD}✖${RESET} $1"; exit 1; }

# ─── Preflight checks ───
command -v claude >/dev/null 2>&1 || fail "claude CLI not found. Install it first: https://docs.anthropic.com/en/docs/claude-code"
command -v git >/dev/null 2>&1    || fail "git not found."

# ─── Check we're in a git repo ───
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not inside a git repository."

# ─── Handle flags ───
AUTO_STAGE=false
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all)       AUTO_STAGE=true; shift ;;
    -y|--yes)       SKIP_CONFIRM=true; shift ;;
    -h|--help)
      echo -e "${BOLD}Usage:${RESET} commit.sh [options]"
      echo ""
      echo "  -a, --all    Stage all modified/deleted files before committing"
      echo "  -y, --yes    Skip confirmation prompt (auto-accept)"
      echo "  -h, --help   Show this help message"
      echo ""
      echo "Examples:"
      echo "  ./scripts/commit.sh          # commit staged files"
      echo "  ./scripts/commit.sh -a       # stage all + commit"
      echo "  ./scripts/commit.sh -a -y    # stage all + commit without asking"
      exit 0
      ;;
    *) fail "Unknown flag: $1. Use --help for usage." ;;
  esac
done

# ─── Stage all if requested ───
if [ "$AUTO_STAGE" = true ]; then
  git add -u
  info "Staged all modified/deleted files."
fi

# ─── Check for staged changes ───
STAGED_FILES=$(git diff --cached --name-only)
if [ -z "$STAGED_FILES" ]; then
  warn "No staged changes found."
  echo ""
  echo -e "  ${DIM}Stage files first:${RESET}  git add <files>"
  echo -e "  ${DIM}Or use:${RESET}            ./scripts/commit.sh -a"
  exit 1
fi

# ─── Show what's staged ───
FILE_COUNT=$(echo "$STAGED_FILES" | wc -l | tr -d ' ')
info "Staged files (${FILE_COUNT}):"
echo "$STAGED_FILES" | while read -r f; do
  echo -e "  ${DIM}•${RESET} $f"
done
echo ""

# ─── Get the diff ───
DIFF=$(git diff --cached --stat && echo "---" && git diff --cached)

# Truncate very large diffs to avoid token limits
MAX_CHARS=12000
if [ ${#DIFF} -gt $MAX_CHARS ]; then
  DIFF="${DIFF:0:$MAX_CHARS}

... [diff truncated at ${MAX_CHARS} chars]"
  warn "Diff was truncated (too large). Message may be less precise."
fi

# ─── Generate commit message via Claude ───
info "Generating commit message..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_FILE="${SCRIPT_DIR}/commit-rules.txt"

if [ ! -f "$RULES_FILE" ]; then
  fail "Rules file not found at ${RULES_FILE}"
fi

RULES=$(cat "$RULES_FILE")

PROMPT="${RULES}

=== GIT DIFF TO ANALYZE ===

${DIFF}"

COMMIT_MSG=$(echo "$PROMPT" | claude -p --model sonnet 2>/dev/null) || fail "Claude CLI failed. Make sure you're authenticated."

# ─── Sanitize output ───
# Remove markdown fencing
COMMIT_MSG=$(echo "$COMMIT_MSG" | sed '/^```/d')

# Strip preamble, trailing junk, and blank lines using awk (portable across macOS/Linux)
COMMIT_MSG=$(echo "$COMMIT_MSG" | awk '
  # Skip markdown fencing
  /^```/ { next }
  # Skip Co-Authored-By / Signed-off-by
  /^Co-Authored-By:/ { next }
  /^Signed-off-by:/ { next }
  # Start capturing from the first line that looks like a conventional commit type
  !started && /^(feat|fix|chore|docs|style|refactor|test|ci|perf|build)/ { started=1 }
  started { lines[++n] = $0 }
  END {
    # Trim trailing blank lines
    while (n > 0 && lines[n] == "") n--
    for (i = 1; i <= n; i++) print lines[i]
  }
')

if [ -z "$COMMIT_MSG" ]; then
  fail "Claude returned an empty or unparseable message. Try again."
fi

# ─── Present the message ───
echo ""
echo -e "${GREEN}${BOLD}Proposed commit message:${RESET}"
echo -e "────────────────────────────────────"
echo -e "${BOLD}${COMMIT_MSG}${RESET}"
echo -e "────────────────────────────────────"
echo ""

# ─── Confirm ───
if [ "$SKIP_CONFIRM" = true ]; then
  ACTION="y"
else
  echo -e "  ${BOLD}y${RESET} — commit with this message"
  echo -e "  ${BOLD}e${RESET} — edit the message before committing"
  echo -e "  ${BOLD}r${RESET} — regenerate a new message"
  echo -e "  ${BOLD}n${RESET} — abort"
  echo ""
  read -rp "$(echo -e "${CYAN}${BOLD}?${RESET} Your choice [y/e/r/n]: ")" ACTION
fi

case "$ACTION" in
  y|Y)
    git commit -m "$COMMIT_MSG"
    ok "Committed!"
    ;;
  e|E)
    TMPFILE=$(mktemp)
    echo "$COMMIT_MSG" > "$TMPFILE"
    ${EDITOR:-vim} "$TMPFILE"
    EDITED_MSG=$(cat "$TMPFILE")
    rm -f "$TMPFILE"
    if [ -z "$EDITED_MSG" ]; then
      fail "Empty commit message. Aborting."
    fi
    git commit -m "$EDITED_MSG"
    ok "Committed with edited message!"
    ;;
  r|R)
    info "Regenerating..."
    exec "$0" $([ "$AUTO_STAGE" = true ] && echo "-a")
    ;;
  *)
    warn "Aborted."
    exit 1
    ;;
esac
