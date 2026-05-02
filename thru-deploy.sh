#!/usr/bin/env bash
# ============================================================
#  thru-deploy.sh
#  Resilient deployment helper for Thru blockchain programs
#  Handles RPC timeouts, connection failures, and smart resume
#  Built by the community, for the community
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

MAX_RETRIES="${THRU_MAX_RETRIES:-20}"
INITIAL_BACKOFF="${THRU_INITIAL_BACKOFF:-15}"
MAX_BACKOFF="${THRU_MAX_BACKOFF:-120}"
BACKOFF_MULTIPLIER="${THRU_BACKOFF_MULTIPLIER:-2}"

log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
log_step()    { echo -e "\n${BOLD}━━━  $* ${RESET}"; }
log_dim()     { echo -e "${DIM}$*${RESET}"; }

print_banner() {
  echo -e "${CYAN}"
  echo "  ┌─────────────────────────────────────────┐"
  echo "  │         thru-deploy  •  by wxxnde        │"
  echo "  │   Resilient deployment for Thru programs  │"
  echo "  └─────────────────────────────────────────┘"
  echo -e "${RESET}"
}

usage() {
  echo -e "${BOLD}Usage:${RESET}"
  echo "  ./thru-deploy.sh <seed> <path-to-binary>"
  echo ""
  echo -e "${BOLD}Examples:${RESET}"
  echo "  ./thru-deploy.sh thru_program2 ./build/thruvm/bin/my_program.bin"
  echo ""
  echo -e "${BOLD}Environment variables (optional):${RESET}"
  echo "  THRU_MAX_RETRIES        Max retry attempts         (default: 20)"
  echo "  THRU_INITIAL_BACKOFF    Initial wait in seconds    (default: 15)"
  echo "  THRU_MAX_BACKOFF        Max wait between retries   (default: 120)"
  echo "  THRU_BACKOFF_MULTIPLIER Backoff growth factor      (default: 2)"
  exit 1
}

if [[ $# -lt 2 ]]; then
  print_banner
  usage
fi

SEED="$1"
BINARY="$2"

if [[ ! -f "$BINARY" ]]; then
  log_error "Binary not found: $BINARY"
  exit 1
fi

if ! command -v thru &> /dev/null; then
  log_error "'thru' CLI not found. Install with: cargo install thru"
  exit 1
fi

classify_error() {
  local output="$1"
  if echo "$output" | grep -q "Connection refused"; then
    echo "node_down"
  elif echo "$output" | grep -q "upstream request timeout\|upstream connect error\|Timeout expired\|TimeoutExpired\|operation was cancelled"; then
    echo "timeout"
  elif echo "$output" | grep -q "NONCE_TOO_LOW"; then
    echo "nonce_too_low"
  elif echo "$output" | grep -q "Account not available error in meta account"; then
    echo "meta_conflict"
  elif echo "$output" | grep -q "Key.*already exists"; then
    echo "key_exists"
  else
    echo "unknown"
  fi
}

main() {
  print_banner

  BINARY_SIZE=$(wc -c < "$BINARY")
  log_step "Deploying Program"
  log_info "Seed:    ${BOLD}$SEED${RESET}"
  log_info "Binary:  ${BOLD}$BINARY${RESET} (${BINARY_SIZE} bytes)"
  log_info "Config:  max_retries=${MAX_RETRIES}, initial_backoff=${INITIAL_BACKOFF}s, max_backoff=${MAX_BACKOFF}s"

  ATTEMPT=0
  BACKOFF=$INITIAL_BACKOFF
  START_TIME=$(date +%s)

  while [[ $ATTEMPT -lt $MAX_RETRIES ]]; do
    ATTEMPT=$((ATTEMPT + 1))
    ELAPSED=$(( $(date +%s) - START_TIME ))

    echo ""
    log_info "Attempt ${BOLD}${ATTEMPT}/${MAX_RETRIES}${RESET} ${DIM}(elapsed: ${ELAPSED}s)${RESET}"
    log_dim "Running: thru program create $SEED $BINARY"

    set +e
    CMD_OUTPUT=$(thru program create "$SEED" "$BINARY" 2>&1)
    CMD_EXIT=$?
    set -e

    echo "$CMD_OUTPUT" | sed "s/^/  ${DIM}/" | sed "s/$/${RESET}/"

    if [[ $CMD_EXIT -eq 0 ]] && echo "$CMD_OUTPUT" | grep -q "Permanent managed program created successfully\|Program uploaded to temporary buffer successfully\|Managed program created successfully"; then
      TOTAL_TIME=$(( $(date +%s) - START_TIME ))
      echo ""
      log_success "${GREEN}${BOLD}Program deployed successfully!${RESET}"
      log_success "Total time: ${TOTAL_TIME}s across ${ATTEMPT} attempt(s)"
      echo ""
      echo -e "${BOLD}━━━  Program Details  ━━━${RESET}"
      echo "$CMD_OUTPUT" | grep -E "Program account:|Meta account:|Signature:" | while IFS= read -r line; do
        echo -e "  ${GREEN}▸${RESET} $line"
      done
      echo ""
      log_info "Save your program account address — you'll need it for all transactions."
      exit 0
    fi

    ERROR_TYPE=$(classify_error "$CMD_OUTPUT")

    case $ERROR_TYPE in
      node_down)
        log_warn "Alphanet node is down (connection refused). Waiting ${BACKOFF}s..."
        ;;
      timeout)
        log_warn "RPC timeout at this step. Waiting ${BACKOFF}s before retry..."
        ;;
      nonce_too_low)
        log_success "Nonce too low — transaction already landed. Verifying account..."
        thru account info default 2>/dev/null || true
        log_info "If your account shows Nonce > 0, deployment likely succeeded. Check manually:"
        log_info "  thru account info default"
        exit 0
        ;;
      meta_conflict)
        log_error "Meta account conflict detected (0x0504)."
        log_error "The previous seed '${SEED}' has a corrupted state."
        NEW_SEED="${SEED}_v$((ATTEMPT + 1))"
        log_warn "Suggestion: retry with a new seed:"
        log_warn "  ./thru-deploy.sh ${NEW_SEED} ${BINARY}"
        exit 1
        ;;
      key_exists)
        log_warn "Key already exists — this is fine, continuing..."
        ;;
      unknown)
        log_warn "Unknown error (exit code: ${CMD_EXIT}). Waiting ${BACKOFF}s..."
        ;;
    esac

    log_dim "Next attempt in ${BACKOFF}s... (Ctrl+C to abort)"
    sleep "$BACKOFF"

    BACKOFF=$(( BACKOFF * BACKOFF_MULTIPLIER ))
    if [[ $BACKOFF -gt $MAX_BACKOFF ]]; then
      BACKOFF=$MAX_BACKOFF
    fi
  done

  echo ""
  log_error "Exhausted ${MAX_RETRIES} attempts without success."
  log_error "Alphanet may be experiencing extended downtime."
  log_info  "Check status in the Thru Discord: discord.gg/thru"
  log_info  "Your upload state is preserved — retry later with the same command."
  exit 1
}

main "$@"
