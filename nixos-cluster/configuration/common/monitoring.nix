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

    # Ensure Kubernetes Helm is available (avoid GUI 'helm' package)
    environment.systemPackages = [ pkgs.kubernetes-helm ];

    # One-shot installer/upgrader that runs after k3s is online
    systemd.services.kube-prometheus-stack-install = {
      description = "Install/Upgrade kube-prometheus-stack via Helm";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = 10;
      };
      path = [ pkgs.kubectl pkgs.kubernetes-helm pkgs.coreutils pkgs.gnugrep pkgs.bash ];
      script = ''
        set -euo pipefail
        KCONF=/etc/rancher/k3s/k3s.yaml
        export KUBECONFIG="$KCONF"
        # Wait for kubeconfig file and API readiness
        for i in $(seq 1 120); do
          if [ -f "$KCONF" ] && kubectl --kubeconfig="$KCONF" get --raw=/readyz >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Add repo and install/upgrade
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
        helm repo update >/dev/null 2>&1 || true

        # Create namespace if missing
        kubectl --kubeconfig="$KCONF" get ns ${cfg.namespace} >/dev/null 2>&1 || kubectl --kubeconfig="$KCONF" create ns ${cfg.namespace}

        helm upgrade --install ${cfg.releaseName} prometheus-community/kube-prometheus-stack \
          --namespace ${cfg.namespace} \
          --values /etc/monitoring/kps-values.yaml \
          --wait
      '';
    };
  };
}


