#!/usr/bin/env bash
set -euo pipefail

echo "📈 Prometheus Access"
echo "===================="
echo
echo "Ingress (if configured): https://prometheus.locallier.com"
echo "Port-forward (alternative):"
echo "  ssh vega 'kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090'"
echo "  Then open http://localhost:9090"
echo
echo "No password is required for Prometheus by default."


