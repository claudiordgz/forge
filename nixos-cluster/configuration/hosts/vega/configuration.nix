{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./k3s.nix
  ];

  locallier.kubePrometheusStack = {
    enable = true;
    valuesYAML = ''
      grafana:
        ingress:
          enabled: true
          ingressClassName: nginx
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt-prod
          hosts:
            - "grafana.locallier.com"
          tls:
            - hosts:
                - "grafana.locallier.com"
              secretName: grafana-tls
      prometheus:
        ingress:
          enabled: true
          ingressClassName: nginx
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt-prod
          hosts:
            - "prometheus.locallier.com"
          tls:
            - hosts:
                - "prometheus.locallier.com"
              secretName: prometheus-tls
    '';
  };
  networking.hostName = "vega";
}

