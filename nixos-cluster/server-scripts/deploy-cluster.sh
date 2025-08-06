#!/bin/bash

# Deploy NixOS Configuration to All Cluster Nodes
# This script deploys configuration changes to all nodes in parallel

set -e

# Configuration
NODES=("vega" "rigel" "arcturus")
CONFIG_DIR="configuration"
SSH_USER="${SSH_USER:-root}"

echo "🚀 Deploying NixOS configuration to all cluster nodes..."
echo "========================================================"

# Function to deploy to a single node
deploy_node() {
    local node=$1
    echo "📦 Deploying to $node..."
    
    # SSH to the node and run nixos-rebuild with better error handling
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node" << 'EOF'
        set -e
        cd /root/forge/nixos-cluster/configuration
        
        # First do a dry run to catch configuration errors
        echo "🔍 Checking configuration for $node..."
        if ! sudo nixos-rebuild dry-activate --flake .#$node > /tmp/deploy.log 2>&1; then
            echo "❌ Configuration check failed for $node:"
            cat /tmp/deploy.log
            exit 1
        fi
        
        # If dry run succeeds, do the actual deployment
        echo "🚀 Applying configuration to $node..."
        if ! sudo nixos-rebuild switch --flake .#$node >> /tmp/deploy.log 2>&1; then
            echo "❌ Deployment failed for $node:"
            cat /tmp/deploy.log
            exit 1
        fi
        
        echo "✅ $node deployed successfully"
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
        echo "🎉 All nodes deployed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Check cluster status: ssh vega 'kubectl get nodes'"
        echo "2. Check k3s services: ssh vega 'systemctl status k3s'"
        echo "3. Check GPU nodes: ssh vega 'kubectl get nodes -l accelerator=nvidia'"
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