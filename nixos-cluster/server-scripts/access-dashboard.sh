#!/bin/bash

# Access Kubernetes Dashboard
# This script provides instructions to access the Kubernetes Dashboard

echo "🌐 Kubernetes Dashboard Access"
echo "=============================="
echo ""
echo "Dashboard URL: https://10.10.10.5:30443"
echo ""
echo "To access the dashboard:"
echo "1. Open your browser and go to: https://10.10.10.5:30443"
echo "2. Accept the self-signed certificate warning"
echo "3. You'll need a token to log in"
echo ""
echo "To get a token, run this command on vega:"
echo "  ssh vega 'kubectl -n kubernetes-dashboard create token kubernetes-dashboard'"
echo ""
echo "Or create a service account with admin privileges:"
echo "  kubectl create serviceaccount dashboard-admin"
echo "  kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin"
echo "  kubectl create token dashboard-admin"
echo ""
echo "📊 Dashboard Features:"
echo "- View all nodes, pods, services"
echo "- Monitor resource usage"
echo "- View logs and events"
echo "- Manage deployments"
echo "- GPU node information"
echo ""
echo "🔒 Security Note: Dashboard is only accessible from your local network (10.10.10.0/24)" 

ssh vega 'kubectl -n kubernetes-dashboard create token kubernetes-dashboard' | pbcopy
echo "Token copied to clipboard"
echo "Paste it into the dashboard login page"
