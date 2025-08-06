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
  - Email: admin@example.com (placeholder - needs real email)
  - Production Let's Encrypt server

## Deployment

These manifests are automatically deployed by the NixOS configuration in `configuration/common/k3s.nix` when the cluster starts.

## SSL Certificate Setup

### ⚠️ Important Note: Let's Encrypt Limitations

**Let's Encrypt requires a publicly accessible domain** for certificate validation. For local networks, you have these options:

### Option 1: Use a Real Domain (Recommended)
1. **Register a real domain** (e.g., `yourdomain.com`)
2. **Point it to your public IP** or use a dynamic DNS service
3. **Update the issuer** with your real domain and email
4. **Access via**: `https://dashboard.yourdomain.com`

### Option 2: Self-Signed Certificates (Current Setup)
- **Current dashboard** uses self-signed certificates
- **Access via**: `https://10.10.10.5:30443`
- **Browser warning**: Accept the certificate manually
- **Perfect for local development/testing**

### Option 3: Local CA (Advanced)
- Create your own Certificate Authority
- Sign certificates for local domains
- Import CA certificate into browsers

### Option 4: mkcert (Development)
- Use `mkcert` to create locally-trusted certificates
- Automatically trusted by browsers
- Great for development environments

## Current Status

The cert-manager is installed and ready, but the Let's Encrypt issuer needs:
1. **Real email address** (not `admin@example.com`)
2. **Public domain** for validation
3. **DNS configuration** pointing to your cluster

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