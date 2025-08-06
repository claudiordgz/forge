#!/bin/bash

# Check Cluster Status
# This script provides a comprehensive overview of the k3s cluster status

set -e

# Configuration
CONTROL_PLANE="vega"
WORKER_NODES=("rigel" "arcturus")
SSH_USER="${SSH_USER:-root}"

echo "🔍 Checking k3s cluster status..."
echo "=================================="

# Function to check node status
check_node() {
    local node=$1
    local role=$2
    
    echo ""
    echo "📋 $role Node: $node"
    echo "----------------------------------------"
    
    # Check if node is reachable
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node" "echo 'Connection successful'" >/dev/null 2>&1; then
        echo "❌ Cannot reach $node"
        return 1
    fi
    
    # Check k3s service status
    echo "🔧 k3s Service Status:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node" "systemctl is-active k3s" 2>/dev/null || echo "❌ k3s service not running"
    
    # Check k3s process
    echo "🔄 k3s Process:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node" "ps aux | grep k3s | grep -v grep | head -1" 2>/dev/null || echo "❌ k3s process not found"
    
    # Check GPU status
    echo "🎮 GPU Status:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node" "nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader,nounits" 2>/dev/null || echo "❌ GPU not available"
    
    # Check system resources
    echo "💾 System Resources:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node" "free -h | grep '^Mem:' | awk '{print \"Memory: \" \$2 \" total, \" \$3 \" used, \" \$4 \" free\"}'" 2>/dev/null || echo "❌ Cannot get memory info"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node" "df -h / | tail -1 | awk '{print \"Disk: \" \$2 \" total, \" \$3 \" used, \" \$4 \" free\"}'" 2>/dev/null || echo "❌ Cannot get disk info"
}

# Function to check cluster-wide status
check_cluster() {
    echo ""
    echo "🌐 Cluster Overview"
    echo "----------------------------------------"
    
    # Check if control plane is reachable
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "echo 'Connection successful'" >/dev/null 2>&1; then
        echo "❌ Cannot reach control plane ($CONTROL_PLANE)"
        return 1
    fi
    
    # Get cluster nodes
    echo "📊 Cluster Nodes:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "kubectl get nodes -o wide" 2>/dev/null || echo "❌ Cannot get node list"
    
    # Get cluster pods
    echo ""
    echo "📦 System Pods:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "kubectl get pods -A --field-selector=status.phase=Running | head -10" 2>/dev/null || echo "❌ Cannot get pod list"
    
    # Get cluster services
    echo ""
    echo "🔗 Cluster Services:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "kubectl get services -A" 2>/dev/null || echo "❌ Cannot get service list"
    
    # Get cluster events (recent)
    echo ""
    echo "📝 Recent Events:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "kubectl get events --sort-by='.lastTimestamp' | tail -5" 2>/dev/null || echo "❌ Cannot get events"
    
    # Check cluster health
    echo ""
    echo "❤️  Cluster Health:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "kubectl get componentstatuses" 2>/dev/null || echo "❌ Cannot get component status"
}

# Function to check GPU nodes specifically
check_gpu_nodes() {
    echo ""
    echo "🎮 GPU Node Details"
    echo "----------------------------------------"
    
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "echo 'Connection successful'" >/dev/null 2>&1; then
        echo "❌ Cannot reach control plane to check GPU nodes"
        return 1
    fi
    
    # Get nodes with GPU labels
    echo "🔍 Nodes with GPU labels:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "kubectl get nodes -l accelerator=nvidia" 2>/dev/null || echo "❌ No GPU nodes found or cannot query"
    
    # Get GPU model information
    echo ""
    echo "📋 GPU Models by Node:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$CONTROL_PLANE" "kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.metadata.labels.gpu\.model}{\"\n\"}{end}'" 2>/dev/null || echo "❌ Cannot get GPU model info"
}

# Main execution
main() {
    # Check control plane
    check_node "$CONTROL_PLANE" "Control Plane"
    
    # Check worker nodes
    for node in "${WORKER_NODES[@]}"; do
        check_node "$node" "Worker"
    done
    
    # Check cluster-wide status
    check_cluster
    
    # Check GPU-specific information
    check_gpu_nodes
    
    echo ""
    echo "✅ Cluster status check completed!"
    echo ""
    echo "💡 Quick Commands:"
    echo "  ssh $CONTROL_PLANE 'kubectl get nodes'     # List all nodes"
    echo "  ssh $CONTROL_PLANE 'kubectl get pods -A'   # List all pods"
    echo "  ssh $CONTROL_PLANE 'kubectl get svc -A'    # List all services"
}

# Parse command line arguments
case "${1:-}" in
    "nodes")
        echo "🔍 Checking node status only..."
        check_node "$CONTROL_PLANE" "Control Plane"
        for node in "${WORKER_NODES[@]}"; do
            check_node "$node" "Worker"
        done
        ;;
    "cluster")
        echo "🌐 Checking cluster status only..."
        check_cluster
        ;;
    "gpu")
        echo "🎮 Checking GPU nodes only..."
        check_gpu_nodes
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  Full cluster status check"
        echo "  nodes      Check node status only"
        echo "  cluster    Check cluster status only"
        echo "  gpu        Check GPU nodes only"
        echo "  help       Show this help message"
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