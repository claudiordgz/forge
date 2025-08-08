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
echo

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


