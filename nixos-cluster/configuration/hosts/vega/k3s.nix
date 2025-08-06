{ config, lib, pkgs, inputs, ... }:

let
  # Path to the dashboard manifest file
  dashboardManifestFile = ../../../kubernetes/dashboard.yaml;

  # Path to Let's Encrypt issuer manifest file
  letsencryptIssuerManifestFile = ../../../kubernetes/letsencrypt-issuer.yaml;

  # Path to dashboard certificate manifest file
  dashboardCertificateManifestFile = ../../../kubernetes/dashboard-certificate.yaml;

  # Path to nginx-ingress manifest file
  nginxIngressManifestFile = ../../../kubernetes/nginx-ingress.yaml;

  # Path to the keys directory from the flake input
  keysDir = inputs.keys;
in {
  # Deploy Kubernetes Dashboard automatically when k3s starts
  systemd.services.k3s-dashboard = {
    description = "Deploy Kubernetes Dashboard";
    wantedBy = [ "k3s.service" ];
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${dashboardManifestFile}";
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${dashboardManifestFile} --ignore-not-found=true";
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
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml --ignore-not-found=true";
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
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete secret cloudflare-api-token-secret -n cert-manager --ignore-not-found=true";
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
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml --ignore-not-found=true";
    };
  };

  # Deploy Let's Encrypt issuer after nginx-ingress
  systemd.services.k3s-letsencrypt-issuer = {
    description = "Deploy Let's Encrypt ClusterIssuer";
    wantedBy = [ "k3s-nginx-ingress.service" ];
    after = [ "k3s-nginx-ingress.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${letsencryptIssuerManifestFile}";
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${letsencryptIssuerManifestFile} --ignore-not-found=true";
    };
  };

  # Deploy dashboard certificate after Let's Encrypt issuer and dashboard
  systemd.services.k3s-dashboard-certificate = {
    description = "Deploy Dashboard Certificate";
    wantedBy = [ "k3s-letsencrypt-issuer.service" ];
    after = [ "k3s-letsencrypt-issuer.service" "k3s-dashboard.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${dashboardCertificateManifestFile}";
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${dashboardCertificateManifestFile} --ignore-not-found=true";
    };
  };
} 