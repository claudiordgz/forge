#!/usr/bin/env bash
set -euo pipefail

echo "📈 Prometheus Access"
echo "===================="
echo
echo "Ingress (if configured): https://prometheus.locallier.com"
echo "Port-forward (alternative):"
echo "  ssh vega 'kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090'"
echo "  Then open http://10.10.10.5:9090"
echo "  Or if remote port 9090 is busy, use a different remote/local mapping:"
echo "  ssh -L 39090:localhost:39091 vega 'kubectl -n monitoring port-forward --address 127.0.0.1 svc/kube-prometheus-stack-prometheus 39091:9090'"
echo "  Then open http://localhost:39090"
echo

# Optional cleanup: pass --kill to terminate any lingering port-forwards on vega for these ports
if [[ "${1:-}" == "--kill" ]]; then
  echo "🔧 Cleaning up lingering kubectl port-forwards on vega (Prometheus ports)..."
  # Also clean up any local background SSH port-forwards targeting Prometheus
  if pgrep -f "ssh .*vega.*port-forward.*kube-prometheus-stack-prometheus" >/dev/null 2>&1; then
    echo "Killing local ssh port-forward processes..."
    pkill -f "ssh .*vega.*port-forward.*kube-prometheus-stack-prometheus" || true
  fi

  ssh vega '
set -eu

# Helper to extract PIDs listening on a TCP port and kill them
kill_port() {
  port="$1"
  # Try via fuser first
  sudo fuser -k "${port}/tcp" >/dev/null 2>&1 || true
  # Then parse ss for any remaining listeners and kill their PIDs
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

# Ensure target ports are freed (remote listener for PF and any previous leftovers)
for port in 9090 39090 39091; do
  kill_port "$port"
done

# Wait up to ~5s for ports to fully release
for i in 1 2 3 4 5; do
  if sudo ss -lntp | egrep -q ":9090|:39090|:39091"; then
    sleep 1
  else
    break
  fi
done

# Show final state
if sudo ss -lntp | egrep ":9090|:39090|:39091"; then
  echo "⚠️ Some ports still appear bound above. If stuck in D-state, a node reboot may be required."
else
  echo "ports 9090/39090/39091 free"
fi
'
  echo "✅ Cleanup attempted (see output above)."
  echo
fi

echo "No password is required for Prometheus by default."


