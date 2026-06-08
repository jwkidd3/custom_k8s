#!/bin/bash
###############################################################################
# Cloud9 Lab Environment Setup
# Installs all tools and connects to the EKS cluster.
# Run this once after creating your Cloud9 environment and attaching the
# k8s-lab-role IAM role.
#
# Usage:  bash setup-cloud9.sh <your-name>
# Example: bash setup-cloud9.sh jsmith
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

CLUSTER_NAME="platform-lab"
REGION="us-east-2"

# ─── Validate input ────────────────────────────────────────────────────────

if [ -z "${1:-}" ]; then
  echo -e "${RED}Usage: bash setup-cloud9.sh <your-name>${NC}"
  echo "Example: bash setup-cloud9.sh jsmith"
  exit 1
fi

STUDENT_NAME="$1"

# Must be valid in namespace names, service accounts, and app names (RFC 1123)
if ! echo "$STUDENT_NAME" | grep -Eq '^[a-z][a-z0-9-]{0,19}$'; then
  echo -e "${RED}ERROR: Invalid student name: $STUDENT_NAME${NC}"
  echo "Use lowercase letters, digits, and hyphens only (start with a letter,"
  echo "20 characters max). No dots, underscores, or uppercase."
  echo "Examples: jsmith, alice-w"
  exit 1
fi

echo "Setting up environment for student: $STUDENT_NAME"

# ─── Verify IAM role ───────────────────────────────────────────────────────

echo ""
echo "==> Verifying IAM role..."
CALLER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)
if echo "$CALLER" | grep -q "k8s-lab-role"; then
  echo -e "${GREEN}IAM role verified: $CALLER${NC}"
else
  echo -e "${RED}ERROR: Expected k8s-lab-role but got: $CALLER${NC}"
  echo "Make sure you have:"
  echo "  1. Disabled Cloud9 managed credentials (Cloud9 > Preferences > AWS Settings)"
  echo "  2. Attached k8s-lab-role to your Cloud9 EC2 instance"
  exit 1
fi

# ─── Install kubectl ───────────────────────────────────────────────────────

echo ""
echo "==> Installing kubectl..."
# Pin to the 1.33 channel to stay within kubectl's ±1 minor-version skew of the cluster
curl -sLO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable-1.33.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# ─── Install Helm ──────────────────────────────────────────────────────────

echo ""
echo "==> Installing Helm..."
curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ─── Install Flux CLI ──────────────────────────────────────────────────────

echo ""
echo "==> Installing Flux CLI..."
curl -s https://fluxcd.io/install.sh | sudo bash

# ─── Install ArgoCD CLI ───────────────────────────────────────────────────

echo ""
echo "==> Installing ArgoCD CLI..."
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# ─── Install jq and envsubst ──────────────────────────────────────────────

echo ""
echo "==> Installing jq and envsubst..."
if command -v yum &>/dev/null; then
  sudo yum install -y jq gettext -q
elif command -v dnf &>/dev/null; then
  sudo dnf install -y jq gettext -q
fi

# ─── Connect to EKS ───────────────────────────────────────────────────────

echo ""
echo "==> Connecting to EKS cluster: $CLUSTER_NAME ($REGION)..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

# ─── Set STUDENT_NAME in shell profile ─────────────────────────────────────

PROFILE="$HOME/.bashrc"
if ! grep -q "export STUDENT_NAME=" "$PROFILE" 2>/dev/null; then
  echo "export STUDENT_NAME=$STUDENT_NAME" >> "$PROFILE"
  echo "Added STUDENT_NAME to $PROFILE"
fi
export STUDENT_NAME

# ─── Verify everything ────────────────────────────────────────────────────

echo ""
echo "=== Tool Versions ==="
kubectl version --client --short 2>/dev/null || kubectl version --client
helm version --short
flux --version
argocd version --client --short 2>/dev/null || argocd version --client
jq --version
envsubst --version
git --version
docker --version
openssl version

echo ""
echo "=== Cluster Connectivity ==="
kubectl cluster-info
kubectl config current-context

echo ""
echo -e "${GREEN}=== Setup complete ===${NC}"
echo "Student: $STUDENT_NAME"
echo ""
echo "STUDENT_NAME has been added to ~/.bashrc so it persists across terminal sessions."
echo "For the current terminal, run: export STUDENT_NAME=$STUDENT_NAME"
