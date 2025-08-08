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
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt-prod
        ingress:
          enabled: true
          ingressClassName: nginx
          hosts: [ "grafana.locallier.com" ]
          tls:
            - hosts: [ "grafana.locallier.com" ]
              secretName: grafana-tls
      prometheus:
        ingress:
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt-prod
        ingress:
          enabled: true
          ingressClassName: nginx
          hosts: [ "prometheus.locallier.com" ]
          tls:
            - hosts: [ "prometheus.locallier.com" ]
              secretName: prometheus-tls
    '';
  };
  networking.hostName = "vega";
}

