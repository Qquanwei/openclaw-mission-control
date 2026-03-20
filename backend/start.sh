#!/bin/bash

TUNNEL_MODE=false
shift_args=()

# Parse arguments (detect --tunnel but don't remove it from args)
for arg in "$@"; do
  if [ "$arg" = "--tunnel" ]; then
    TUNNEL_MODE=true
  else
    shift_args+=("$arg")
  fi
done

if [ "$TUNNEL_MODE" = true ]; then
  echo "[start.sh] Starting with Cloudflare Tunnel..."

  # Check if cloudflared is installed
  if ! command -v cloudflared &> /dev/null; then
    echo "[start.sh] ERROR: cloudflared is not installed."
    echo "[start.sh] Install it with: brew install cloudflared (macOS) or apt install cloudflared (Linux)"
    exit 1
  fi

  # Use temp file to capture cloudflared output
  TMPFILE=$(mktemp)
  cloudflared tunnel --url http://localhost:8000 > "$TMPFILE" 2>&1 &
  CLOUDFLARED_PID=$!

  # Extract URL from output (format: |  https://xxx.trycloudflare.com  |)
  TUNNEL_URL=""
  for i in {1..30}; do
    if grep -q "trycloudflare.com" "$TMPFILE" 2>/dev/null; then
      TUNNEL_URL=$(grep -o 'https://[^ ]*trycloudflare.com[^ ]*' "$TMPFILE" | head -1)
      [ -n "$TUNNEL_URL" ] && break
    fi
    sleep 1
  done

  if [ -z "$TUNNEL_URL" ]; then
    echo "[start.sh] ERROR: Failed to get tunnel URL"
    cat "$TMPFILE"
    kill $CLOUDFLARED_PID 2>/dev/null
    rm -f "$TMPFILE"
    exit 1
  fi

  echo "[start.sh] Tunnel URL: $TUNNEL_URL"
  export BASE_URL="$TUNNEL_URL"

  # Cleanup on exit
  cleanup() {
    echo "[start.sh] Shutting down tunnel..."
    kill $CLOUDFLARED_PID 2>/dev/null
    rm -f "$TMPFILE"
  }
  trap cleanup EXIT
fi

uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 "${shift_args[@]}"
