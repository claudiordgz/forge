{ config, pkgs, lib, ... }:

let
  cfg = config.locallier.kubePrometheusStack;
in {
  options.locallier.kubePrometheusStack = {
    enable = lib.mkEnableOption "Install/upgrade kube-prometheus-stack via Helm at boot";

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "monitoring";
      description = "Kubernetes namespace to install kube-prometheus-stack";
    };

    releaseName = lib.mkOption {
      type = lib.types.str;
      default = "kube-prometheus-stack";
      description = "Helm release name";
    };

    valuesYAML = lib.mkOption {
      type = lib.types.lines;
      default = ''
        grafana:
          service:
            type: ClusterIP
          ingress:
            enabled: false
        prometheus:
          ingress:
            enabled: false
        alertmanager:
          ingress:
            enabled: false
      '';
      description = "Helm values.yaml for kube-prometheus-stack";
    };
  };

  config = lib.mkIf cfg.enable {
    # Values file rendered to /etc so systemd unit can reference it
    environment.etc."monitoring/kps-values.yaml".text = cfg.valuesYAML;

    # Ensure helm is available (kubectl is already provided elsewhere)
    environment.systemPackages = [ pkgs.helm ];

    # One-shot installer/upgrader that runs after k3s is online
    systemd.services.kube-prometheus-stack-install = {
      description = "Install/Upgrade kube-prometheus-stack via Helm";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      path = [ pkgs.kubectl pkgs.helm pkgs.coreutils pkgs.gnugrep pkgs.bash ];
      script = ''
        set -euo pipefail
        # Wait for API to be reachable
        for i in $(seq 1 60); do
          if kubectl get --raw=/readyz >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Add repo and install/upgrade
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
        helm repo update >/dev/null 2>&1 || true

        # Create namespace if missing
        kubectl get ns ${cfg.namespace} >/dev/null 2>&1 || kubectl create ns ${cfg.namespace}

        helm upgrade --install ${cfg.releaseName} prometheus-community/kube-prometheus-stack \
          --namespace ${cfg.namespace} \
          --values /etc/monitoring/kps-values.yaml \
          --wait
      '';
    };
  };
}


