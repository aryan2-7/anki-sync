#!/usr/bin/env bash
# Run a self-hosted Anki sync server and expose it over Tailscale.
# Starts Tailscale if it's off, and Ctrl+C stops the server and the
# tailscale serve rule cleanly.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load optional config from .env (see .env.example)
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  . "$SCRIPT_DIR/.env"
  set +a
fi

export SYNC_HOST="${SYNC_HOST:-127.0.0.1}"
export SYNC_PORT="${SYNC_PORT:-8080}"
export SYNC_BASE="${SYNC_BASE:-$SCRIPT_DIR/data}"
PYTHON="${ANKI_PYTHON:-$SCRIPT_DIR/venv/bin/python}"

# Sanity checks
if [ -z "${SYNC_USER1:-}" ]; then
  echo "Error: SYNC_USER1 is not set. Copy .env.example to .env and edit it." >&2
  exit 1
fi
if ! command -v tailscale >/dev/null 2>&1; then
  echo "Error: tailscale is not installed or not in PATH." >&2
  exit 1
fi
if [ ! -x "$PYTHON" ]; then
  echo "Error: Python not found at $PYTHON (set ANKI_PYTHON or create the venv)." >&2
  exit 1
fi

get_state() {
  tailscale status --json 2>/dev/null \
    | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null
}

# Make sure Tailscale is running and logged in before starting anything.
ensure_tailscale() {
  local state launched=0
  for _ in $(seq 1 30); do
    state=$(get_state)
    case "$state" in
      Running)
        return 0
        ;;
      Stopped|NeedsLogin)
        echo "Tailscale is $state, connecting..."
        tailscale up
        ;;
      *)
        if [ "$launched" -eq 0 ]; then
          launched=1
          if [ "$(uname)" = "Darwin" ]; then
            echo "Tailscale isn't running, opening it..."
            open -a Tailscale
          else
            echo "Tailscale isn't running, trying to start tailscaled..."
            sudo systemctl start tailscaled 2>/dev/null \
              || echo "Could not start tailscaled automatically. Start it manually." >&2
          fi
        fi
        ;;
    esac
    sleep 1
  done
  echo "Error: couldn't get Tailscale running." >&2
  exit 1
}

SERVER_PID=""

cleanup() {
  trap - INT TERM EXIT
  echo
  echo "Shutting down..."
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
  tailscale serve reset
  echo "Done."
  exit 0
}

# Before the trap, so a Tailscale failure exits with 1 instead of 0
ensure_tailscale
trap cleanup INT TERM EXIT

mkdir -p "$SYNC_BASE"
tailscale serve --bg "$SYNC_PORT"

URL=$(tailscale status --json | "$PYTHON" -c "import sys,json; print('https://' + json.load(sys.stdin)['Self']['DNSName'].rstrip('.') + '/')")
echo "Sync URL: $URL"
echo

"$PYTHON" -m anki.syncserver &
SERVER_PID=$!
wait "$SERVER_PID"
