{ config, lib, pkgs, inputs, ... }:

let
  # Longhorn
  longhornManifestUrl = "https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml";

  metallbManifestUrl = "https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml";
  metallbIPAddressPoolFile = ../../../kubernetes/metallb/ipaddresspool.yaml;
  metallbL2AdvertisementFile = ../../../kubernetes/metallb/l2advertisement.yaml;

  cloudflaredDeploymentFile = ../../../kubernetes/cloudflared/deployment.yaml;
  cloudflaredDashboardConfig = ../../../kubernetes/cloudflared/hosts-dashboard.yaml;
  harborValuesFile = ../../../kubernetes/registry/harbor-values.yaml;

  # Path to the keys directory from the flake input
  keysDir = inputs.keys;
in {
  # Deploy cert-manager automatically when k3s starts
  systemd.services.k3s-cert-manager = {
    description = "Deploy cert-manager";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml";
    };
  };

  # Install/Upgrade Harbor via Helm (namespace ai)
  systemd.services.k3s-harbor = {
    description = "Install/Upgrade Harbor (ai namespace)";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" "k3s-longhorn.service" ];
    restartTriggers = [ harborValuesFile ];
    path = [ pkgs.kubectl pkgs.kubernetes-helm pkgs.coreutils pkgs.gnugrep pkgs.bash ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = pkgs.writeShellScript "install-harbor" ''
        set -euo pipefail
        KCONF=/etc/rancher/k3s/k3s.yaml
        export KUBECONFIG="$KCONF"

        # Wait for API
        for i in $(seq 1 120); do
          if [ -f "$KCONF" ] && kubectl get --raw=/readyz >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Create namespace if missing
        kubectl get ns ai >/dev/null 2>&1 || kubectl create ns ai

        # Ensure Helm repo
        helm repo add harbor https://helm.goharbor.io >/dev/null 2>&1 || true
        helm repo update >/dev/null 2>&1 || true

        # Require admin secret to exist (created out of band via file)
        if ! kubectl -n ai get secret harbor-admin >/dev/null 2>&1; then
          echo "harbor-admin Secret missing in ns ai (key HARBOR_ADMIN_PASSWORD). Skipping Harbor install." >&2
          exit 0
        fi

        # Install/upgrade Harbor
        helm upgrade --install harbor harbor/harbor \
          -n ai \
          -f ${harborValuesFile} \
          --wait
      '';
    };
  };

  # Deploy Cloudflare Tunnel (cloudflared) to publish selected services via Zero Trust
  systemd.services.k3s-cloudflared = {
    description = "Deploy Cloudflare Tunnel (cloudflared)";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    restartTriggers = [ cloudflaredDeploymentFile ];
    path = [ pkgs.kubectl pkgs.jq pkgs.coreutils pkgs.bash ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = pkgs.writeShellScript "deploy-cloudflared" ''
        set -euo pipefail
        KCONF=/etc/rancher/k3s/k3s.yaml
        export KUBECONFIG="$KCONF"

        # Ensure namespace exists
        kubectl get ns cloudflared >/dev/null 2>&1 || kubectl create ns cloudflared

        # Only proceed if the secret already exists (managed by deploy script)
        if ! kubectl -n cloudflared get secret cloudflared-token >/dev/null 2>&1; then
          echo "cloudflared-token Secret missing in ns cloudflared. Skipping cloudflared deploy." >&2
          exit 0
        fi

        # Apply dashboard hostname mapping (configmap)
        kubectl apply -f ${cloudflaredDashboardConfig}

        # Apply Deployment (token-based)
        kubectl apply -f ${cloudflaredDeploymentFile}
      '';
    };
  };

  # Removed: Cloudflare API token secret creation (handled by deploy script)

  # Deploy nginx-ingress
  systemd.services.k3s-nginx-ingress = {
    description = "Deploy nginx-ingress controller";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml --validate=false";
    };
  };

  # Install MetalLB (CRDs + controllers)
  systemd.services.k3s-metallb = {
    description = "Deploy MetalLB (native manifests)";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${metallbManifestUrl} --validate=false";
    };
  };

  # Configure MetalLB address pool + L2 advertisement after CRDs are ready
  systemd.services.k3s-metallb-config = {
    description = "Configure MetalLB IPAddressPool and L2Advertisement";
    wantedBy = [ "k3s-metallb.service" ];
    after = [ "k3s-metallb.service" ];
    restartTriggers = [ metallbIPAddressPoolFile metallbL2AdvertisementFile ];
    path = [ pkgs.kubectl pkgs.coreutils pkgs.gnugrep pkgs.bash ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = pkgs.writeShellScript "configure-metallb" ''
        set -euo pipefail
        # Wait for CRDs to be established
        for i in $(seq 1 120); do
          if kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1 && \
             kubectl get crd l2advertisements.metallb.io >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Create namespace just in case (apply is idempotent)
        kubectl create ns metallb-system >/dev/null 2>&1 || true

        # Apply pool and L2Advertisement
        kubectl apply -f ${metallbIPAddressPoolFile}
        kubectl apply -f ${metallbL2AdvertisementFile}
      '';
    };
  };

  # Dashboard resources removed (managed externally or via Tunnel)

  # Deploy Longhorn distributed storage system
  systemd.services.k3s-longhorn = {
    description = "Deploy Longhorn Distributed Storage";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f ${longhornManifestUrl}";
      # ExecStop removed on purpose to avoid tearing down CRDs/webhooks
    };
  };

  # Patch nginx-ingress Service to LoadBalancer using MetalLB
  systemd.services.k3s-nginx-ingress-lb = {
    description = "Switch ingress-nginx controller Service to LoadBalancer (MetalLB)";
    wantedBy = [ "k3s-metallb-config.service" "k3s-nginx-ingress.service" ];
    after = [ "k3s-metallb-config.service" "k3s-nginx-ingress.service" ];
    path = [ pkgs.kubectl pkgs.jq pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = pkgs.writeShellScript "patch-ingress-to-lb" ''
        set -euo pipefail
        # Wait for the Service to exist
        for i in $(seq 1 120); do
          if kubectl -n ingress-nginx get svc ingress-nginx-controller >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Patch to LoadBalancer with a fixed IP from MetalLB pool
        kubectl -n ingress-nginx patch svc ingress-nginx-controller \
          --type=merge -p '{
            "spec": {
              "type": "LoadBalancer",
              "externalTrafficPolicy": "Local",
              "loadBalancerIP": "10.10.10.80"
            }
          }'
      '';
    };
  };
} 