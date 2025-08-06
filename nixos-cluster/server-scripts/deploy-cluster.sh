#!/bin/bash

# Deploy NixOS Configuration to All Cluster Nodes
# This script deploys configuration changes to all nodes in parallel

set -e

# Configuration
NODES=("vega" "rigel" "arcturus")
CONFIG_DIR="configuration"
SSH_USER="${SSH_USER:-root}"
CONTROL_PLANE="vega" # Assuming vega is the control plane

echo "🚀 Deploying NixOS configuration to all cluster nodes..."
echo "========================================================"

# Function to deploy to a single node
deploy_node() {
    local node=$1
    echo "📦 Deploying to $node..."
    
    # For vega (control plane), we need to save the Cloudflare API token to a file
    if [ "$node" = "vega" ]; then
        echo "🔑 Fetching Cloudflare API token from 1Password..."
        
        # Fetch the Cloudflare API token and save it to a file on vega
        if ! CLOUDFLARE_API_TOKEN=$(op item get cloudflare-locallier.com-token --field password --reveal 2>/dev/null); then
            echo "❌ Failed to get Cloudflare API token from 1Password"
            exit 1
        fi
        
        echo "📁 Saving Cloudflare API token to vega..."
        ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" "mkdir -p /var/lib/nixos-cluster/keys && echo '$CLOUDFLARE_API_TOKEN' > /var/lib/nixos-cluster/keys/cloudflare-api-token && chmod 600 /var/lib/nixos-cluster/keys/cloudflare-api-token"
        echo "✅ Saved Cloudflare API token to vega"
    fi
    
    # SSH to the node and run nixos-rebuild with better error handling
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" << EOF
        set -e
        NODE_NAME="$node"
        cd /root/forge
        
        # First pull latest changes
        echo "🔄 Pulling latest changes for \$NODE_NAME..."
        git reset --hard HEAD || true
        git clean -fd || true
        git fetch origin main
        git reset --hard origin/main
        
        cd nixos-cluster/configuration
        
        # First do a dry run to catch configuration errors
        echo "🔍 Checking configuration for \$NODE_NAME..."
        if ! sudo nixos-rebuild dry-activate --flake .#\$NODE_NAME > /tmp/deploy.log 2>&1; then
            echo "❌ Configuration check failed for \$NODE_NAME:"
            cat /tmp/deploy.log
            exit 1
        fi
        
        # If dry run succeeds, do the actual deployment
        echo "🚀 Applying configuration to \$NODE_NAME..."
        if ! sudo nixos-rebuild switch --flake .#\$NODE_NAME >> /tmp/deploy.log 2>&1; then
            echo "❌ Deployment failed for \$NODE_NAME:"
            cat /tmp/deploy.log
            exit 1
        fi
        
        echo "✅ \$NODE_NAME deployed successfully"
EOF
    then
        echo "✅ $node deployed successfully"
    else
        echo "❌ Failed to deploy to $node"
        return 1
    fi
}

# Function to check node connectivity
check_connectivity() {
    local node=$1
    echo "🔍 Checking connectivity to $node..."
    
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node" "echo 'Connection successful'" >/dev/null 2>&1; then
        echo "✅ $node is reachable"
        return 0
    else
        echo "❌ Cannot reach $node"
        return 1
    fi
}

# Main deployment logic
main() {
    # Check if 1Password CLI is signed in, sign in if not
    if ! op whoami &>/dev/null; then
        echo "🔐  1Password CLI not signed in — signing in…"
        eval "$(op signin --account https://my.1password.com)"
        echo "✅  Signed in."
    fi
    
    echo "🔍 Checking node connectivity..."
    local reachable_nodes=()
    
    for node in "${NODES[@]}"; do
        if check_connectivity "$node"; then
            reachable_nodes+=("$node")
        fi
    done
    
    if [ ${#reachable_nodes[@]} -eq 0 ]; then
        echo "❌ No nodes are reachable. Check your SSH configuration."
        exit 1
    fi
    
    echo ""
    echo "📋 Deploying to ${#reachable_nodes[@]} nodes: ${reachable_nodes[*]}"
    echo ""
    
    # Deploy to all reachable nodes in parallel
    local pids=()
    for node in "${reachable_nodes[@]}"; do
        deploy_node "$node" &
        pids+=($!)
    done
    
    # Wait for all deployments to complete
    local failed=0
    for pid in "${pids[@]}"; do
        wait $pid
        if [ $? -ne 0 ]; then
            failed=1
        fi
    done
    
    echo ""
    if [ $failed -eq 0 ]; then
        echo ""
        echo "🎉 All nodes deployed successfully!"
        echo ""
        echo "🔧 Fixing worker nodes to join the cluster..."
        echo "=============================================="
        
        # Get the join token from vega
        echo "📋 Getting join token from control plane ($CONTROL_PLANE)..."
        JOIN_TOKEN=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "cat /var/lib/rancher/k3s/server/node-token")
        
        if [ -z "$JOIN_TOKEN" ]; then
            echo "❌ Failed to get join token from $CONTROL_PLANE"
            exit 1
        fi
        
        echo "✅ Got join token from $CONTROL_PLANE"
        
        # Fix worker nodes to join the cluster
        for node in "${reachable_nodes[@]}"; do
            if [ "$node" != "$CONTROL_PLANE" ]; then
                echo ""
                echo "🔧 Fixing worker node: $node"
                echo "----------------------------------------"
                
                # Stop k3s service
                echo "🛑 Stopping k3s service on $node..."
                ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" "systemctl stop k3s" || true
                
                # Wait a moment for the service to stop
                sleep 3
                
                # Copy the join token
                echo "📋 Copying join token to $node..."
                ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" "echo '$JOIN_TOKEN' > /var/lib/rancher/k3s/server/node-token"
                
                # Start k3s service
                echo "🚀 Starting k3s service on $node..."
                ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" "systemctl start k3s"
                
                # Wait for the service to start
                sleep 5
                
                # Check if the service is running
                if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" "systemctl is-active k3s" 2>/dev/null; then
                    echo "✅ k3s service is running on $node"
                else
                    echo "❌ k3s service failed to start on $node"
                fi
            fi
        done
        
        echo ""
        echo "🎉 Deployment and cluster join completed!"
        echo ""
        echo "Next steps:"
        echo "1. Wait a few minutes for nodes to join the cluster"
        echo "2. Check cluster status: ./check-cluster.sh"
        echo "3. Check nodes: ssh vega 'kubectl get nodes'"
        echo "4. Check GPU nodes: ssh vega 'kubectl get nodes -l accelerator=nvidia'"
    else
        echo "⚠️  Some deployments failed. Check the output above."
        exit 1
    fi
}

# Parse command line arguments
case "${1:-}" in
    "check")
        echo "🔍 Checking node connectivity only..."
        for node in "${NODES[@]}"; do
            check_connectivity "$node"
        done
        ;;
    "single")
        if [ -z "$2" ]; then
            echo "❌ Usage: $0 single <node-name>"
            echo "Available nodes: ${NODES[*]}"
            exit 1
        fi
        if [[ " ${NODES[*]} " =~ " $2 " ]]; then
            deploy_node "$2"
        else
            echo "❌ Unknown node: $2"
            echo "Available nodes: ${NODES[*]}"
            exit 1
        fi
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  Deploy to all nodes in parallel"
        echo "  check      Check connectivity to all nodes"
        echo "  single     Deploy to a single node"
        echo "  help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Deploy to all nodes"
        echo "  $0 check              # Check connectivity"
        echo "  $0 single vega        # Deploy only to vega"
        echo ""
        echo "Environment variables:"
        echo "  SSH_USER              # SSH username (default: root)"
        ;;
    "")
        main
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac 