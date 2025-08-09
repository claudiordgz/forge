#!/usr/bin/env bash
set -euo pipefail

# This script is intended to be copied to vega and executed there.
# It fixes Longhorn CRDs/BackupTarget and (re)deploys Harbor with the no-backup StorageClass.

KCONF="/etc/rancher/k3s/k3s.yaml"
export KUBECONFIG="$KCONF"

ROOT_DIR="/root/forge/nixos-cluster"
SC_NOBACKUP="$ROOT_DIR/kubernetes/longhorn-storageclass-nobackup.yaml"
BT_DEFAULT="$ROOT_DIR/kubernetes/longhorn-backuptarget-default.yaml"
HARBOR_VALUES="$ROOT_DIR/kubernetes/registry/harbor-values.yaml"

echo "==> Ensuring Longhorn CRDs exist"
if ! kubectl get crd volumes.longhorn.io >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/install/01-crd.yaml
fi

echo "==> Applying default BackupTarget (if CRD present)"
if kubectl get crd backuptargets.longhorn.io >/dev/null 2>&1; then
  kubectl apply -f "$BT_DEFAULT" || true
else
  echo "WARN: backuptargets.longhorn.io CRD not found yet; continuing"
fi

echo "==> Applying no-backup StorageClass"
kubectl apply -f "$SC_NOBACKUP"

echo "==> Removing any previous Harbor release and dangling PVCs"
helm uninstall harbor -n ai --wait 2>/dev/null || true
kubectl -n ai delete pvc -l release=harbor 2>/dev/null || true

echo "==> Installing/Upgrading Harbor with longhorn-nobackup StorageClass"
helm repo add harbor https://helm.goharbor.io >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true

helm upgrade --install harbor harbor/harbor -n ai -f "$HARBOR_VALUES" \
  --set persistence.persistentVolumeClaim.registry.storageClass=longhorn-nobackup \
  --set persistence.persistentVolumeClaim.chartmuseum.storageClass=longhorn-nobackup \
  --set persistence.persistentVolumeClaim.jobservice.jobLog.storageClass=longhorn-nobackup \
  --set persistence.persistentVolumeClaim.database.storageClass=longhorn-nobackup \
  --set persistence.persistentVolumeClaim.redis.storageClass=longhorn-nobackup \
  --set persistence.persistentVolumeClaim.trivy.storageClass=longhorn-nobackup

echo "==> Current Harbor PVCs and Pods"
kubectl -n ai get pvc,pods

echo "Done. If PVCs are still Pending, check Longhorn manager logs and CRDs."

