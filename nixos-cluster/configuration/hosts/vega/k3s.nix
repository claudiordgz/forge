{ config, lib, pkgs, inputs, ... }:

let
  # Path to the dashboard manifest file
  dashboardManifestFile = ../../../kubernetes/dashboard.yaml;

  # Path to Let's Encrypt issuer manifest file
  letsencryptIssuerManifestFile = ../../../kubernetes/letsencrypt-issuer.yaml;

  # Path to dashboard certificate manifest file
  dashboardCertificateManifestFile = ../../../kubernetes/dashboard-certificate.yaml;

  # Path to Longhorn manifest file
  longhornManifestFile = ../../../kubernetes/longhorn.yaml;

  # Path to Longhorn NodePort service file
  longhornNodePortServiceFile = ../../../kubernetes/longhorn-nodeport-service.yaml;

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

  # Configure Longhorn UI NodePort after Longhorn deployment
  systemd.services.k3s-longhorn-nodeport = {
    description = "Configure Longhorn UI NodePort";
    wantedBy = [ "k3s-longhorn.service" ];
    after = [ "k3s-longhorn.service" ];
    restartTriggers = [ longhornNodePortServiceFile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = pkgs.writeShellScript "configure-longhorn-nodeport" ''
        # Wait for Longhorn to be ready
        ${pkgs.kubectl}/bin/kubectl wait --for=condition=ready pod -l app=longhorn-ui -n longhorn-system --timeout=300s
        
        # Apply the NodePort service
        ${pkgs.kubectl}/bin/kubectl apply --server-side --force-conflicts -f ${longhornNodePortServiceFile}
      '';
    };
  };
} 