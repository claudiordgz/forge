# Kubernetes Manifests

This directory contains Kubernetes manifests that are automatically deployed with the cluster.

## Files

### `dashboard.yaml`
- **Purpose**: Kubernetes Dashboard for web-based cluster monitoring
- **Access**: https://10.10.10.5:30443 or https://dashboard.locallier.com
- **Features**: 
  - View nodes, pods, services, deployments
  - Monitor resource usage
  - View logs and events
  - GPU node information
- **Security**: Only accessible from local network (10.10.10.0/24)

### `nginx-ingress.yaml`
- **Purpose**: nginx-ingress controller for HTTP-01 challenge support
- **Features**:
  - Enables HTTP-01 challenge for Let's Encrypt certificates
  - Provides ingress functionality for services
  - Exposed on NodePort 30080 (HTTP) and 30443 (HTTPS)

### `letsencrypt-issuer.yaml`
- **Purpose**: Let's Encrypt ClusterIssuer for SSL certificates
- **Configuration**:
  - Uses HTTP-01 challenge for domain `locallier.com`
  - Email: claudio.rdgz+forge@gmail.com
  - Production Let's Encrypt server

### `dashboard-certificate.yaml`
- **Purpose**: SSL certificate for the Kubernetes Dashboard
- **Domain**: dashboard.locallier.com, k8s.locallier.com
- **Automatic renewal**: Managed by cert-manager

### `longhorn.yaml`
- **Purpose**: Longhorn distributed storage system
- **Features**:
  - Distributed block storage across cluster nodes
  - Data replication for high availability
  - Web UI for storage management
  - Uses local drives on vega (476.9 GB) and rigel (931.5 GB)
- **Access**: Port-forward to longhorn-frontend service

## Deployment

These manifests are automatically deployed by the NixOS configuration:

- **Shared k3s configuration**: `configuration/common/k3s.nix` (k3s service, containerd, firewall)
- **Control plane services**: `configuration/hosts/vega/k3s.nix` (dashboard, cert-manager, Let's Encrypt)
- **Worker nodes**: Only get the shared k3s configuration

The control plane services (dashboard, cert-manager, certificates, longhorn) are only deployed on the vega node.

## SSL Certificate Setup

### ✅ Let's Encrypt with locallier.com

**Your setup is now configured for production SSL certificates!**

### Domain Configuration
1. **DNS Records**: Point these subdomains to your cluster IP:
   ```
   dashboard.locallier.com  →  10.10.10.5
   k8s.locallier.com        →  10.10.10.5
   ```

2. **Certificate Management**:
   - cert-manager automatically requests certificates from Let's Encrypt
   - Uses DNS-01 challenge for validation
   - Certificates auto-renew before expiration
   - Stored in Kubernetes secrets

### Access URLs
- **Dashboard**: https://dashboard.locallier.com
- **Alternative**: https://k8s.locallier.com

### Current Status
- ✅ **cert-manager** installed and running
- ✅ **Let's Encrypt issuer** configured for locallier.com
- ✅ **Dashboard certificate** will be created automatically
- ✅ **Infrastructure as code** (reproducible)

## Longhorn Storage Setup

### ✅ Distributed Storage with Longhorn

**Your cluster now has distributed storage capabilities!**

### Storage Configuration
1. **Available Drives**:
   - **vega**: 476.9 GB unused drive (`/dev/nvme0n1`)
   - **rigel**: 931.5 GB unused drive (`/dev/nvme0n1`)

2. **Longhorn Features**:
   - Distributed block storage across all nodes
   - Automatic data replication for high availability
   - Web UI for storage management
   - Persistent volumes for Kubernetes workloads

### Access Longhorn UI
```bash
# Port-forward to access the web UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
```
Then visit: http://localhost:8080

### Configure Storage Backends
1. Access Longhorn UI
2. Go to **Node** tab
3. Click on a node (vega/rigel)
4. Add disk path (e.g., `/mnt/storage`)
5. Mount the unused drives:
   ```bash
   # On vega
   sudo mkdir -p /mnt/storage && sudo mount /dev/nvme0n1 /mnt/storage
   
   # On rigel  
   sudo mkdir -p /mnt/storage && sudo mount /dev/nvme0n1 /mnt/storage
   ```

### Current Status
- ✅ **Longhorn** will be deployed automatically
- ✅ **Infrastructure as code** (reproducible)
- ⏳ **Storage backends** need to be configured after deployment

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