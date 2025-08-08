{ config, lib, pkgs, inputs, ... }:

let
  # Path to the dashboard manifest file
  dashboardManifestFile = ../../../kubernetes/dashboard.yaml;

  # Path to the dashboard ingress manifest
  dashboardIngressManifestFile = ../../../kubernetes/dashboard-ingress.yaml;

  # Path to Let's Encrypt issuer manifest file
  letsencryptIssuerManifestFile = ../../../kubernetes/letsencrypt-issuer.yaml;

  # Path to dashboard certificate manifest file
  dashboardCertificateManifestFile = ../../../kubernetes/dashboard-certificate.yaml;

  # Path to Longhorn manifest file
  longhornManifestFile = ../../../kubernetes/longhorn.yaml;

  # Longhorn UI will be exposed via Ingress through MetalLB; NodePort no longer used

  # Path to Longhorn ingress
  longhornIngressManifestFile = ../../../kubernetes/longhorn-ingress.yaml;

  # MetalLB manifests
  metallbManifestUrl = "https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml";
  metallbIPAddressPoolFile = ../../../kubernetes/metallb-ipaddresspool.yaml;
  metallbL2AdvertisementFile = ../../../kubernetes/metallb-l2advertisement.yaml;

  # Cloudflared (Cloudflare Tunnel) manifests
  cloudflaredDeploymentFile = ../../../kubernetes/cloudflared/deployment.yaml;

  # Path to the keys directory from the flake input
  keysDir = inputs.keys;
in {
  # Deploy Kubernetes Dashboard automatically when k3s starts
  systemd.services.k3s-dashboard = {
    description = "Deploy Kubernetes Dashboard";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    restartTriggers = [ dashboardManifestFile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f ${dashboardManifestFile}";
    };
  };

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

        # Expect a token file at ${keysDir}/cloudflared/tunnel-token
        TOKEN_FILE="${keysDir}/cloudflared/tunnel-token"
        if [ ! -f "$TOKEN_FILE" ]; then
          echo "Missing Cloudflare tunnel token at $TOKEN_FILE" >&2
          echo "Place the token (single line) there and rebuild" >&2
          exit 1
        fi

        # Create/Update secret with token
        kubectl -n cloudflared create secret generic cloudflared-token \
          --from-file=TUNNEL_TOKEN="$TOKEN_FILE" \
          --dry-run=client -o yaml | kubectl apply -f -

        # Apply Deployment (token-based)
        kubectl apply -f ${cloudflaredDeploymentFile}
      '';
    };
  };

  # Create Cloudflare API token secret from file
  systemd.services.k3s-cloudflare-secret = {
    description = "Deploy Cloudflare API Token Secret from File";
    wantedBy = [ "k3s-cert-manager.service" ];
    after = [ "k3s-cert-manager.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = pkgs.writeShellScript "create-cloudflare-secret" ''
        # Check if the token file exists
        if [ ! -f ${keysDir}/cloudflare-api-token ]; then
          echo "Error: Cloudflare API token file not found at ${keysDir}/cloudflare-api-token"
          exit 1
        fi
        
        # Read the token from the file
        API_TOKEN=$(cat ${keysDir}/cloudflare-api-token)
        
        # Create the secret directly with kubectl
        ${pkgs.kubectl}/bin/kubectl create secret generic cloudflare-api-token-secret \
          --namespace=cert-manager \
          --from-literal=api-token="$API_TOKEN" \
          --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -
      '';
    };
  };

  # Deploy nginx-ingress after cloudflare secret
  systemd.services.k3s-nginx-ingress = {
    description = "Deploy nginx-ingress controller";
    wantedBy = [ "k3s-cloudflare-secret.service" ];
    after = [ "k3s-cloudflare-secret.service" ];
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

  # Deploy Let's Encrypt issuer after nginx-ingress
  systemd.services.k3s-letsencrypt-issuer = {
    description = "Deploy Let's Encrypt ClusterIssuer";
    wantedBy = [ "k3s-nginx-ingress.service" ];
    after = [ "k3s-nginx-ingress.service" ];
    restartTriggers = [ letsencryptIssuerManifestFile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f ${letsencryptIssuerManifestFile}";
      # ExecStop removed on purpose to avoid Let's Encrypt issuer being torn down
    };
  };

  # Deploy dashboard certificate after Let's Encrypt issuer and dashboard
  systemd.services.k3s-dashboard-certificate = {
    description = "Deploy Dashboard Certificate";
    wantedBy = [ "k3s-letsencrypt-issuer.service" ];
    after = [ "k3s-letsencrypt-issuer.service" "k3s-dashboard.service" ];
    restartTriggers = [ dashboardCertificateManifestFile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f ${dashboardCertificateManifestFile}";
      # ExecStop removed on purpose to avoid Let's Encrypt issuer being torn down
    };
  };

  # Deploy dashboard ingress after certificate/issuer and nginx-ingress
  systemd.services.k3s-dashboard-ingress = {
    description = "Deploy Kubernetes Dashboard Ingress";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s-letsencrypt-issuer.service" "k3s-dashboard.service" "k3s-nginx-ingress.service" ];
    restartTriggers = [ dashboardIngressManifestFile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f ${dashboardIngressManifestFile}";
    };
  };

  # Deploy Longhorn distributed storage system
  systemd.services.k3s-longhorn = {
    description = "Deploy Longhorn Distributed Storage";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml";
      # ExecStop removed on purpose to avoid tearing down CRDs/webhooks
    };
  };

  # Removed NodePort configuration for Longhorn; ingress is used instead

  # Longhorn UI Ingress (after nginx and cert-manager)
  systemd.services.k3s-longhorn-ingress = {
    description = "Deploy Longhorn UI Ingress";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s-longhorn.service" "k3s-nginx-ingress.service" "k3s-letsencrypt-issuer.service" ];
    restartTriggers = [ longhornIngressManifestFile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f ${longhornIngressManifestFile}";
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