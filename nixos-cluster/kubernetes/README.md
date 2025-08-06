# Kubernetes Manifests

This directory contains Kubernetes manifests that are automatically deployed with the cluster.

## Files

### `dashboard.yaml`
- **Purpose**: Kubernetes Dashboard for web-based cluster monitoring
- **Access**: https://10.10.10.5:30443
- **Features**: 
  - View nodes, pods, services, deployments
  - Monitor resource usage
  - View logs and events
  - GPU node information
- **Security**: Only accessible from local network (10.10.10.0/24)

### `cert-manager.yaml`
- **Purpose**: cert-manager for automatic SSL certificate management
- **Features**:
  - Automatically manages TLS certificates
  - Integrates with Let's Encrypt for free SSL certificates
  - Supports DNS-01 challenges for local domains

### `letsencrypt-issuer.yaml`
- **Purpose**: Let's Encrypt ClusterIssuer for SSL certificates
- **Configuration**:
  - Uses DNS-01 challenge for local domain `forge.local`
  - Email: admin@forge.local
  - Production Let's Encrypt server

## Deployment

These manifests are automatically deployed by the NixOS configuration in `configuration/common/k3s.nix` when the cluster starts.

## SSL Certificate Setup

### Local Domain Configuration
1. Add to your local DNS or `/etc/hosts`:
   ```
   10.10.10.5    dashboard.forge.local
   ```

2. The cert-manager will automatically:
   - Request certificates from Let's Encrypt
   - Use DNS-01 challenge for verification
   - Store certificates in Kubernetes secrets

### Using Certificates
Once deployed, you can create certificates for services:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dashboard-cert
  namespace: kubernetes-dashboard
spec:
  secretName: dashboard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - dashboard.forge.local
```

## Adding New Manifests

1. Create your YAML file in this directory
2. Add a reference to it in `configuration/common/k3s.nix`
3. Create a systemd service to deploy it automatically

Example:
```nix
# In k3s.nix
myManifestFile = ../../kubernetes/my-app.yaml;

systemd.services.k3s-my-app = lib.mkIf isControlPlane {
  description = "Deploy My App";
  wantedBy = [ "k3s.service" ];
  after = [ "k3s.service" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${pkgs.kubectl}/bin/kubectl apply -f ${myManifestFile}";
    ExecStop = "${pkgs.kubectl}/bin/kubectl delete -f ${myManifestFile} --ignore-not-found=true";
  };
};
``` 