#!/bin/bash
# Terminate the running mux0 Debug app.
set -e

echo "==> Killing running mux0…"
pkill -f "Debug/mux0.app" 2>/dev/null || true
sleep 1

if pgrep -lf "Debug/mux0.app" >/dev/null; then
  echo "!! mux0 still running, sending SIGKILL"
  pkill -9 -f "Debug/mux0.app" 2>/dev/null || true
  sleep 1
fi

if pgrep -lf "Debug/mux0.app" >/dev/null; then
  echo "!! failed to terminate mux0" >&2
  exit 1
else
  echo "==> mux0 terminated"
fi
