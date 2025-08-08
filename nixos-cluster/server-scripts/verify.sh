#!/usr/bin/env bash

# verify.sh — Quick cluster health checks
#
# Usage:
#   ./verify.sh [--all] [--core-dns] [--metrics] [--dashboard] [--longhorn] [--host <control-plane-host>]
#
# Defaults:
#   --all against host "vega"

set -euo pipefail

HOST="vega"
DO_CORE_DNS=false
DO_METRICS=false
DO_DASHBOARD=false
DO_LONGHORN=false

if [[ $# -eq 0 ]]; then
  DO_CORE_DNS=true
  DO_METRICS=true
  DO_DASHBOARD=true
  DO_LONGHORN=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST=${2:?}; shift 2 ;;
    --all)
      DO_CORE_DNS=true; DO_METRICS=true; DO_DASHBOARD=true; DO_LONGHORN=true; shift ;;
    --core-dns)
      DO_CORE_DNS=true; shift ;;
    --metrics)
      DO_METRICS=true; shift ;;
    --dashboard)
      DO_DASHBOARD=true; shift ;;
    --longhorn)
      DO_LONGHORN=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--all] [--core-dns] [--metrics] [--dashboard] [--longhorn] [--host <host>]"; exit 0 ;;
    *)
      echo "Unknown arg: $1"; exit 1 ;;
  esac
done

ok()  { printf "\033[32m✔\033[0m %s\n" "$*"; }
warn(){ printf "\033[33m!\033[0m %s\n" "$*"; }
err() { printf "\033[31m✖\033[0m %s\n" "$*"; }

run() {
  # Run a command on the control-plane host
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$HOST" "$*"
}

failures=0

check_core_dns() {
  echo "== CoreDNS =="
  if ! run "kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide"; then
    err "Failed to list CoreDNS pods"; ((failures++)); return
  fi

  # Ready check
  local ready
  ready=$(run "kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}'" || true)
  if grep -q '^true$' <<<"$ready"; then
    ok "CoreDNS pod Ready"
  else
    err "CoreDNS not Ready"
    # Show recent logs (last 40 lines)
    run "kubectl -n kube-system logs -l k8s-app=kube-dns --tail=40 --all-containers" || true
    ((failures++))
  fi

  # Service exists
  if run "kubectl -n kube-system get svc kube-dns -o wide" >/dev/null 2>&1; then
    ok "kube-dns Service present"
  else
    err "kube-dns Service missing"; ((failures++))
  fi
}

check_metrics() {
  echo "== Metrics =="
  run "kubectl -n kube-system get deploy metrics-server -o wide" || { err "metrics-server deployment missing"; ((failures++)); return; }

  # APIService availability
  local cond
  cond=$(run "kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'" || true)
  if [[ "$cond" == "True" ]]; then
    ok "v1beta1.metrics.k8s.io APIService Available"
  else
    err "metrics APIService not Available"
    run "kubectl describe apiservice v1beta1.metrics.k8s.io" || true
    ((failures++))
  fi
}

check_dashboard() {
  echo "== Dashboard =="
  if ! run "kubectl -n kubernetes-dashboard get pods -o wide"; then
    err "Dashboard namespace or pods missing"; ((failures++)); return
  fi
  # Pod ready
  local dready
  dready=$(run "kubectl -n kubernetes-dashboard get pods -l k8s-app=kubernetes-dashboard -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}'" || true)
  if grep -q '^true$' <<<"$dready"; then ok "Dashboard pod Ready"; else err "Dashboard not Ready"; ((failures++)); fi

  # TLS secret
  if run "kubectl -n kubernetes-dashboard get secret dashboard-tls" >/dev/null 2>&1; then
    ok "dashboard-tls present"
  else
    err "dashboard-tls missing"; ((failures++))
  fi

  # Service type/port
  local svc
  svc=$(run "kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o jsonpath='{.spec.type} {.spec.ports[0].nodePort}'" || true)
  if grep -q '^NodePort 30443$' <<<"$svc"; then
    ok "Dashboard Service NodePort 30443"
  else
    warn "Dashboard Service is not NodePort 30443 (got: $svc)"
  fi
}

check_longhorn() {
  echo "== Longhorn =="
  if ! run "kubectl get ns longhorn-system"; then
    err "longhorn-system namespace missing"; ((failures++)); return
  fi
  run "kubectl -n longhorn-system get pods -o wide" || { err "Failed to list Longhorn pods"; ((failures++)); return; }

  # UI readiness
  local uiready
  uiready=$(run "kubectl -n longhorn-system get pods -l app=longhorn-ui -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}'" || true)
  if grep -q '^true$' <<<"$uiready"; then ok "Longhorn UI Ready"; else warn "Longhorn UI not Ready"; fi

  # Service NodePort
  local lsvc
  lsvc=$(run "kubectl -n longhorn-system get svc longhorn-frontend -o jsonpath='{.spec.type} {.spec.ports[0].nodePort}'" || true)
  if grep -q '^NodePort 30880$' <<<"$lsvc"; then ok "Longhorn UI NodePort 30880"; else warn "Longhorn UI Service not NodePort 30880 (got: $lsvc)"; fi
}

any_selected=false

if $DO_CORE_DNS;   then any_selected=true; check_core_dns; fi
if $DO_METRICS;    then any_selected=true; check_metrics;  fi
if $DO_DASHBOARD;  then any_selected=true; check_dashboard; fi
if $DO_LONGHORN;   then any_selected=true; check_longhorn;  fi

if ! $any_selected; then
  echo "No checks selected. Use --all or specific flags."
  exit 2
fi

echo ""; echo "Summary:"
if [[ $failures -eq 0 ]]; then
  ok "All selected checks passed"
  exit 0
else
  err "$failures check(s) failed"
  exit 1
fi


