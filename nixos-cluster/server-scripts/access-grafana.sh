#!/usr/bin/env bash
set -euo pipefail

echo "📊 Grafana Access"
echo "=================="
echo
echo "Default credentials: user 'admin', password from Grafana secret"
echo
echo "Ingress (if configured): https://grafana.locallier.com"
echo "Port-forward (alternative):"
echo "  ssh vega 'kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80'"
echo "  Then open http://10.10.10.5:3000"
echo "  Or if remote port 3000 is busy, use a different remote/local mapping:"
echo "  ssh -L 33000:localhost:3001 vega 'kubectl -n monitoring port-forward --address 127.0.0.1 svc/kube-prometheus-stack-grafana 3001:80'"
echo "  Then open http://localhost:33000"
echo

# Optional cleanup: pass --kill to terminate any lingering port-forwards on vega
if [[ "${1:-}" == "--kill" ]]; then
  echo "🔧 Cleaning up lingering kubectl port-forwards on vega..."
  # Also clean up any local background SSH port-forwards targeting Grafana
  if pgrep -f "ssh .*vega.*port-forward.*kube-prometheus-stack-grafana" >/dev/null 2>&1; then
    echo "Killing local ssh port-forward processes..."
    pkill -f "ssh .*vega.*port-forward.*kube-prometheus-stack-grafana" || true
  fi

  ssh vega '
set -eu

# Helper to extract PIDs listening on a TCP port and kill them
kill_port() {
  port="$1"
  sudo fuser -k "${port}/tcp" >/dev/null 2>&1 || true
  if sudo ss -lntp "sport = :${port}" 2>/dev/null | grep -q ":${port} "; then
    pids=$(sudo ss -lntp "sport = :${port}" 2>/dev/null | sed -n "s/.*pid=\([0-9]\+\).*/\1/p" | sort -u || true)
    if [ -n "$pids" ]; then
      sudo kill $pids || true
      sleep 1
      sudo kill -9 $pids || true
      for p in $pids; do
        pg=$(ps -o pgid= -p "$p" 2>/dev/null | tr -d " " || true)
        [ -n "$pg" ] && sudo kill -9 -- "-$pg" || true
      done
    fi
  fi
}

# Kill any kubectl port-forward processes first (broader sweep)
pids=$(pgrep -f "kubectl.*port-forward" || true)
if [ -n "$pids" ]; then
  echo "Killing: $pids"
  sudo kill $pids || true
  sleep 1
  sudo kill -9 $pids || true
  for p in $pids; do
    pg=$(ps -o pgid= -p "$p" 2>/dev/null | tr -d " " || true)
    [ -n "$pg" ] && sudo kill -9 -- "-$pg" || true
  done
fi

# Ensure target ports are freed
for port in 3000 3001; do
  kill_port "$port"
done

# Wait up to ~5s for ports to fully release
for i in 1 2 3 4 5; do
  if sudo ss -lntp | egrep -q ":3000|:3001"; then
    sleep 1
  else
    break
  fi
done

# Show final state
if sudo ss -lntp | egrep ":3000|:3001"; then
  echo "⚠️ Some ports still appear bound above. If stuck in D-state, a node reboot may be required."
else
  echo "ports 3000/3001 free"
fi
'
  echo "✅ Cleanup attempted (see output above)."
  echo
fi

echo "🔑 Fetching Grafana admin password from cluster (via vega)..."
if ! PASSWORD=$(ssh vega "kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d" 2>/dev/null); then
  echo "Failed to retrieve password. Ensure kube-prometheus-stack is installed and namespace 'monitoring' exists." >&2
  exit 1
fi

COPIED=false
if command -v pbcopy >/dev/null 2>&1; then
  printf "%s" "$PASSWORD" | pbcopy
  COPIED=true
elif command -v xclip >/dev/null 2>&1; then
  printf "%s" "$PASSWORD" | xclip -selection clipboard
  COPIED=true
elif command -v wl-copy >/dev/null 2>&1; then
  printf "%s" "$PASSWORD" | wl-copy
  COPIED=true
fi

if [[ "$COPIED" == true ]]; then
  echo "✅ Grafana admin password copied to clipboard"
else
  echo "Password (copy manually): $PASSWORD"
fi

echo
echo "Login as: admin"
echo "If login fails, wait a minute and retry (pods may still be starting)."


