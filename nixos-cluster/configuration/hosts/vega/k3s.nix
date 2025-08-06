{ config, lib, pkgs, ... }:

let
  # Path to the dashboard manifest file
  dashboardManifestFile = ../../../kubernetes/dashboard.yaml;

  # Path to Let's Encrypt issuer manifest file
  letsencryptIssuerManifestFile = ../../../kubernetes/letsencrypt-issuer.yaml;

  # Path to dashboard certificate manifest file
  dashboardCertificateManifestFile = ../../../kubernetes/dashboard-certificate.yaml;

  # Path to nginx-ingress manifest file
  nginxIngressManifestFile = ../../../kubernetes/nginx-ingress.yaml;
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

  # Deploy nginx-ingress after cert-manager
  systemd.services.k3s-nginx-ingress = {
    description = "Deploy nginx-ingress controller";
    wantedBy = [ "k3s-cert-manager.service" ];
    after = [ "k3s-cert-manager.service" ];
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

  # Deploy dashboard certificate after Let's Encrypt issuer
  systemd.services.k3s-dashboard-certificate = {
    description = "Deploy Dashboard Certificate";
    wantedBy = [ "k3s-letsencrypt-issuer.service" ];
    after = [ "k3s-letsencrypt-issuer.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [ "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ];
      ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${dashboardCertificateManifestFile}";
      ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${dashboardCertificateManifestFile} --ignore-not-found=true";
    };
  };
} 