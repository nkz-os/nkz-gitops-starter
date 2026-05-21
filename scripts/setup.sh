#!/usr/bin/env bash
# =============================================================================
# Nekazari Platform — GitOps Starter Wizard
# =============================================================================
# Replaces {{PLACEHOLDER}} tokens across all overlay files with your domain
# and infrastructure choices. Run from repo root:
#   chmod +x scripts/setup.sh && ./scripts/setup.sh
# =============================================================================
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

banner() {
  echo -e "${CYAN}"
  echo "╔═════════════════════════════════════════════════╗"
  echo "║   Nekazari Platform — GitOps Starter Wizard     ║"
  echo "║   FIWARE-based multi-tenant agri/industry SaaS  ║"
  echo "╚═════════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

section() {
  echo ""
  echo -e "${BOLD}── $1 ──${RESET}"
  echo ""
}

ask() {
  local var="$1" prompt="$2" default="$3"
  if [ -n "$default" ]; then
    read -r -p "$(echo -e "${CYAN}${prompt} [${default}]:${RESET} ")" value
    value="${value:-$default}"
  else
    read -r -p "$(echo -e "${CYAN}${prompt}:${RESET} ")" value
  fi
  eval "$var=\"$value\""
}

banner

# ── Domain configuration ──────────────────────────────────────────────
section "Domain Configuration"
echo "Nekazari uses dedicated subdomains per service so each can have its own TLS certificate."
echo "You need a wildcard DNS record (*.YOUR_DOMAIN.com) or these individual A/AAAA records"
echo "pointing to your server's public IP."
echo ""

ask BASE_DOMAIN \
    "Base domain (e.g., example.com)"

# Derive defaults from the base domain
DEFAULT_FRONTEND="${BASE_DOMAIN}"
DEFAULT_API="api.${BASE_DOMAIN}"
DEFAULT_KEYCLOAK="auth.${BASE_DOMAIN}"
DEFAULT_MINIO="minio.${BASE_DOMAIN}"
DEFAULT_ARGO="argo.${BASE_DOMAIN}"
DEFAULT_VPN="vpn.${BASE_DOMAIN}"
DEFAULT_ZULIP="messaging.${BASE_DOMAIN}"
DEFAULT_ODOO="odoo.${BASE_DOMAIN}"

section "Subdomain Convention"
echo "Default subdomains derived from ${BASE_DOMAIN}:"
echo ""

ask FRONTEND_DOMAIN "  Frontend (landing + app)"     "$DEFAULT_FRONTEND"
ask API_DOMAIN      "  API backend"                  "$DEFAULT_API"
ask KEYCLOAK_DOMAIN "  Authentication (Keycloak)"    "$DEFAULT_KEYCLOAK"
ask MINIO_DOMAIN    "  Object storage (MinIO)"       "$DEFAULT_MINIO"
ask ARGO_DOMAIN     "  GitOps dashboard (ArgoCD)"    "$DEFAULT_ARGO"
ask VPN_DOMAIN      "  VPN control plane (Headscale)" "$DEFAULT_VPN"

echo ""
echo -e "${YELLOW}Optional modules (leave blank to skip):${RESET}"
echo ""

ask ZULIP_DOMAIN    "  Messaging (Zulip)"            "${DEFAULT_ZULIP}"
ask ODOO_DOMAIN     "  ERP (Odoo)"                   "${DEFAULT_ODOO}"

# ── Organisation ─────────────────────────────────────────────────────
section "Organisation"
ask COMPANY_NAME    "Company/org name (for UI attribution)" "My Company"
ask ADMIN_EMAIL     "Admin email"                           "admin@${BASE_DOMAIN}"

# ── Server ───────────────────────────────────────────────────────────
section "Server Setup (optional)"
echo "If you already have K3s + ArgoCD running, leave this blank."
echo "Otherwise provide the server IP for automated bootstrap."
echo ""

ask SERVER_IP       "Server IP (or leave empty to skip bootstrap)"
SERVER_IP="${SERVER_IP:-}"

if [ -n "$SERVER_IP" ]; then
  ask SERVER_USER   "SSH user" "root"
  echo ""
  echo -e "${YELLOW}The wizard will install K3s, Helm, cert-manager, and ArgoCD on ${SERVER_USER}@${SERVER_IP}.${RESET}"
  echo -e "${YELLOW}This requires SSH key access to the server.${RESET}"
  read -r -p "$(echo -e "${CYAN}Proceed with server bootstrap? [y/N]:${RESET} ")" do_bootstrap
else
  do_bootstrap="n"
fi

# ── Summary ──────────────────────────────────────────────────────────
section "Review"
echo "  Base domain:        ${BOLD}${BASE_DOMAIN}${RESET}"
echo "  Frontend:           ${FRONTEND_DOMAIN}"
echo "  API:                ${API_DOMAIN}"
echo "  Auth (Keycloak):    ${KEYCLOAK_DOMAIN}"
echo "  Object store:       ${MINIO_DOMAIN}"
echo "  GitOps (ArgoCD):    ${ARGO_DOMAIN}"
echo "  VPN (Headscale):    ${VPN_DOMAIN}"
if [ -n "$ZULIP_DOMAIN" ]; then echo "  Messaging (Zulip):  ${ZULIP_DOMAIN}"; fi
if [ -n "$ODOO_DOMAIN" ]; then echo "  ERP (Odoo):         ${ODOO_DOMAIN}"; fi
echo "  Company:            ${COMPANY_NAME}"
echo "  Admin email:        ${ADMIN_EMAIL}"
echo ""

read -r -p "$(echo -e "${CYAN}Apply configuration? [Y/n]:${RESET} ")" do_apply
do_apply="${do_apply:-Y}"
if [ "$do_apply" != "Y" ] && [ "$do_apply" != "y" ]; then
  echo "Aborted."
  exit 0
fi

# ── Apply placeholders ───────────────────────────────────────────────
section "Applying configuration"

PLACEHOLDERS=(
  "s|{{FRONTEND_DOMAIN}}|${FRONTEND_DOMAIN}|g"
  "s|{{API_DOMAIN}}|${API_DOMAIN}|g"
  "s|{{KEYCLOAK_DOMAIN}}|${KEYCLOAK_DOMAIN}|g"
  "s|{{MINIO_DOMAIN}}|${MINIO_DOMAIN}|g"
  "s|{{ARGO_DOMAIN}}|${ARGO_DOMAIN}|g"
  "s|{{VPN_DOMAIN}}|${VPN_DOMAIN}|g"
  "s|{{ZULIP_DOMAIN}}|${ZULIP_DOMAIN}|g"
  "s|{{ODOO_DOMAIN}}|${ODOO_DOMAIN}|g"
  "s|{{COMPANY_NAME}}|${COMPANY_NAME}|g"
  "s|{{ADMIN_EMAIL}}|${ADMIN_EMAIL}|g"
  "s|{{YOUR_DOMAIN}}|${BASE_DOMAIN}|g"
)

COUNT=0
for f in $(find . -name "*.yaml" -o -name "*.json" | grep -v '.git'); do
  for p in "${PLACEHOLDERS[@]}"; do
    sed -i -e "$p" "$f"
  done
  COUNT=$((COUNT + 1))
done

echo "Processed ${COUNT} files."

# Verify no leftover placeholders
LEFTOVER=$(grep -r '\{\{[A-Z_]+\}\}' . --include="*.yaml" --include="*.json" 2>/dev/null | grep -v '.git' || true)
if [ -n "$LEFTOVER" ]; then
  echo ""
  echo -e "${RED}WARNING: Unresolved placeholders found:${RESET}"
  echo "$LEFTOVER"
  echo ""
  echo "Replace them manually or re-run the wizard."
else
  echo -e "${GREEN}All placeholders resolved.${RESET}"
fi

# ── Generate secrets (placeholders for the user to fill) ─────────────
section "Secrets"
echo "The following secrets must be created in the cluster before deploying:"
echo ""
cat <<EOF
  kubectl create secret generic jwt-secret \
    --from-literal=secret="$(openssl rand -hex 32)" -n nekazari

  kubectl create secret generic redis-secret \
    --from-literal=password="$(openssl rand -hex 16)" -n nekazari

  kubectl create secret generic postgresql-secret \
    --from-literal=postgres-url="postgresql://nekazari:$(openssl rand -hex 16)@postgresql-service:5432/nekazari" \
    --from-literal=connection-string="postgresql://nekazari:$(openssl rand -hex 16)@postgresql-service:5432/nekazari" -n nekazari

  kubectl create secret generic minio-secret \
    --from-literal=root-user="minioadmin" \
    --from-literal=root-password="$(openssl rand -hex 16)" -n nekazari

  kubectl create secret generic mongodb-secret \
    --from-literal=root-username="admin" \
    --from-literal=root-password="$(openssl rand -hex 16)" -n nekazari

  kubectl create secret generic keycloak-secret \
    --from-literal=admin-username="admin" \
    --from-literal=admin-password="$(openssl rand -hex 16)" -n nekazari
EOF

echo ""
echo -e "${YELLOW}Save the generated passwords above — they won't be shown again.${RESET}"
echo -e "${YELLOW}For production, use Sealed Secrets, SOPS, or External Secrets Operator.${RESET}"

# ── Server bootstrap ─────────────────────────────────────────────────
if [ "$do_bootstrap" = "y" ] || [ "$do_bootstrap" = "Y" ]; then
  section "Bootstrapping server"
  echo "Installing K3s, cert-manager, and ArgoCD on ${SERVER_USER}@${SERVER_IP}..."

  ssh "${SERVER_USER}@${SERVER_IP}" "bash -s" <<'BOOTSTRAP'
set -e

# K3s (lightweight Kubernetes)
if ! command -v kubectl &>/dev/null; then
  echo "Installing K3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
  mkdir -p ~/.kube
  sudo k3s kubectl config view --raw > ~/.kube/config
  sudo chown $(id -u):$(id -g) ~/.kube/config
fi

# Helm
if ! command -v helm &>/dev/null; then
  echo "Installing Helm..."
  curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# cert-manager
echo "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait

# ArgoCD
echo "Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.extraArgs[0]="--insecure" \
  --wait

echo ""
echo "Server bootstrap complete."
echo "ArgoCD password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
BOOTSTRAP

  echo ""
  echo -e "${GREEN}Server bootstrap complete.${RESET}"
  echo "Apply the ArgoCD root app:"
  echo ""
  echo "  kubectl apply -f bootstrap/root-config.yaml"
fi

# ── Done ─────────────────────────────────────────────────────────────
section "Next Steps"
echo ""
echo -e "${GREEN}Configuration applied. Next steps:${RESET}"
echo ""
echo "1. Create secrets in the cluster (see secrets section above)"
echo ""
echo "2. Commit and push this repo to your own private GitHub/GitLab:"
echo ""
echo "     git init && git add -A"
echo "     git commit -m 'Nekazari platform configured for ${BASE_DOMAIN}'"
echo "     git remote add origin https://github.com/YOUR_ORG/nkz-gitops-config.git"
echo "     git push -u origin main"
echo ""
echo "3. Create the ArgoCD root app pointing to your repo:"
echo ""
echo "     kubectl apply -f bootstrap/root-config.yaml"
echo ""
echo "   Or if your repo is private, first create an ArgoCD repository secret:"
echo ""
echo "     kubectl -n argocd create secret generic my-repo-creds \\"
echo "       --from-literal=type=git \\"
echo "       --from-literal=url=https://github.com/YOUR_ORG/nkz-gitops-config \\"
echo "       --from-literal=password=\$GITHUB_TOKEN"
echo ""
echo "   Then update bootstrap/root-config.yaml to reference your repo URL."
echo ""
echo "4. Wait for ArgoCD to sync (watch -n5 'kubectl get apps -n argocd')"
echo ""
echo "5. Create DNS records for:"
echo "     ${FRONTEND_DOMAIN}"
echo "     ${API_DOMAIN}"
echo "     ${KEYCLOAK_DOMAIN}"
echo "     ${MINIO_DOMAIN}"
echo "     ${ARGO_DOMAIN}"
if [ -n "$VPN_DOMAIN" ] && [ "$VPN_DOMAIN" != "${BASE_DOMAIN}" ]; then
  echo "     ${VPN_DOMAIN}"
fi
if [ -n "$ZULIP_DOMAIN" ]; then echo "     ${ZULIP_DOMAIN}"; fi
if [ -n "$ODOO_DOMAIN" ]; then echo "     ${ODOO_DOMAIN}"; fi
echo ""
echo "   All pointing to your server IP: ${SERVER_IP:-<your-server-ip>}"
echo ""
echo -e "${GREEN}Visit https://${KEYCLOAK_DOMAIN}/auth to access the admin console.${RESET}"
echo ""
