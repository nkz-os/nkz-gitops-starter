# Nekazari Platform — GitOps Starter

Zero-to-production FIWARE-based multi-tenant platform in under 10 minutes.
This repo contains the **production configuration overlays** for Nekazari.

> **What this is:** A GitOps starter kit that deploys the full Nekazari stack
> (Context Broker, auth, API gateway, 15+ modules, monitoring) on any K3s cluster
> via ArgoCD. The wizard replaces placeholders with your domain and deploys
> everything automatically.
>
> **License:** AGPL-3.0

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                     YOUR SERVER                            │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │  K3s    │  │ cert-    │  │ Traefik  │  │ ArgoCD    │  │
│  │ (k8s)   │  │ manager  │  │ (ingress)│  │ (gitops)  │  │
│  └─────────┘  └──────────┘  └──────────┘  └───────────┘  │
│       │                           │              │         │
│  ┌────┴───────────────────────────┴──────────────┴──────┐ │
│  │                  Nekazari Platform                    │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐  │ │
│  │  │Orion-LD │ │Keycloak │ │PostgreSQL│ │  Modules  │  │ │
│  │  │(NGSI-LD)│ │ (OIDC)  │ │+Timescale│ │  (15+)    │  │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └───────────┘  │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐  │ │
│  │  │ MongoDB │ │  MinIO  │ │  Redis  │ │  Mosquitto │  │ │
│  │  │(context)│ │(objects)│ │ (cache) │ │  (MQTT)    │  │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └───────────┘  │ │
│  └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

### Two-Repo GitOps Pattern

```
nkz-gitops-starter (this repo, public)     YOUR private fork
     ┌─────────────────────────┐           ┌──────────────────────┐
     │  overlays/core/         │  ──wizard──▶ │  overlays/core/     │
     │  {{FRONTEND_DOMAIN}}    │           │  nekazari.example.com│
     │  overlays/modules/      │           │  overlays/modules/   │
     │  {{API_DOMAIN}}         │           │  api.example.com     │
     │  config/*.yaml          │           │  config/*.yaml       │
     │  bootstrap/             │           │  bootstrap/          │
     └─────────────────────────┘           └──────────────────────┘
                                                     │
                                            ArgoCD syncs from
                                            your private fork
                                                     │
                                                     ▼
                                              K3s cluster
```

The public `nkz-os/nkz` repo holds **templates with placeholders**.
This repo holds the **production overlays** that ArgoCD applies on top.
The wizard replaces `{{PLACEHOLDER}}` tokens with your actual domains.

## Prerequisites

### DNS Records

Create these DNS records pointing to your server IP **before deploying**:

| Subdomain | Service | Required |
|-----------|---------|----------|
| `(your domain)` | Frontend (landing + app) | **Yes** |
| `api.(your domain)` | API Gateway | **Yes** |
| `auth.(your domain)` | Keycloak SSO | **Yes** |
| `minio.(your domain)` | Object storage (MinIO) | **Yes** |
| `argo.(your domain)` | ArgoCD GitOps dashboard | **Yes** |
| `vpn.(your domain)` | VPN control plane (Headscale) | Optional |
| `messaging.(your domain)` | Zulip communications | Optional |
| `odoo.(your domain)` | Odoo ERP | Optional |

> **Tip:** A wildcard record (`*.your-domain.com`) covers all of them.

### Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disk | 40 GB | 80+ GB SSD |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |
| Ports | 80, 443, 6443 | — |

### Software

- `openssl` (for generating random secrets locally)
- SSH key access to server (if using bootstrap)
- A GitHub/GitLab account (for your private fork)

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/nkz-os/nkz-gitops-starter
cd nkz-gitops-starter

# 2. Run the wizard
./scripts/setup.sh

# 3. Answer the prompts:
#    → Domain: example.com
#    → Subdomains: (accept defaults)
#    → Company: My Company
#    → Server IP: 1.2.3.4 (optional, for bootstrap)

# 4. Create the secrets in your cluster
#    (the wizard prints kubectl commands — copy-paste them)

# 5. Commit and push to your private fork
git init && git add -A
git commit -m "Nekazari platform configured for example.com"
git remote add origin https://github.com/YOUR_ORG/nkz-gitops-config
git push -u origin main

# 6. Apply the ArgoCD root app
kubectl apply -f bootstrap/root-config.yaml

# 7. Watch ArgoCD sync the platform
watch kubectl get apps -n argocd

# 8. Access Keycloak admin at https://auth.example.com/auth
```

## Manual Setup (without wizard)

If you prefer to configure manually:

1. Replace all `{{PLACEHOLDER}}` tokens across `config/` and `overlays/`:
   ```bash
   find . -name "*.yaml" -exec sed -i \
     -e 's/{{FRONTEND_DOMAIN}}/your-domain.com/g' \
     -e 's/{{API_DOMAIN}}/api.your-domain.com/g' \
     -e 's/{{KEYCLOAK_DOMAIN}}/auth.your-domain.com/g' \
     -e 's/{{MINIO_DOMAIN}}/minio.your-domain.com/g' \
     -e 's/{{ARGO_DOMAIN}}/argo.your-domain.com/g' \
     -e 's/{{VPN_DOMAIN}}/vpn.your-domain.com/g' \
     -e 's/{{COMPANY_NAME}}/Your Company/g' \
     -e 's/{{ADMIN_EMAIL}}/admin@your-domain.com/g' \
     {} \;
   ```

2. Create required K8s secrets (see Secrets section below).

3. Follow steps 5-8 from Quick Start above.

## Secrets

The following secrets must exist in the `nekazari` namespace before ArgoCD
syncs the platform. The wizard generates random values for you; save them.

| Secret | Keys | Purpose |
|--------|------|---------|
| `jwt-secret` | `secret` | JWT signing (RS256), HMAC fallback |
| `redis-secret` | `password` | Redis cache and job queue |
| `postgresql-secret` | `postgres-url`, `connection-string` | Primary database |
| `minio-secret` | `root-user`, `root-password` | S3-compatible object storage |
| `mongodb-secret` | `root-username`, `root-password` | Orion-LD entity registry |
| `keycloak-secret` | `admin-username`, `admin-password` | SSO admin console |

**For production**, do NOT store secrets as plain K8s Secrets. Use one of:
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) (encrypted, git-friendly)
- [External Secrets Operator](https://external-secrets.io/) (AWS/GCP/Vault)
- [SOPS](https://github.com/getsops/sops) (multi-backend encryption)

## Placeholder Reference

| Placeholder | Default value | Where used |
|-------------|--------------|------------|
| `{{FRONTEND_DOMAIN}}` | `example.com` | Landing page, frontend host |
| `{{API_DOMAIN}}` | `api.example.com` | API Gateway ingress, CORS |
| `{{KEYCLOAK_DOMAIN}}` | `auth.example.com` | SSO URLs, JWT issuers |
| `{{MINIO_DOMAIN}}` | `minio.example.com` | Object storage public URL |
| `{{ARGO_DOMAIN}}` | `argo.example.com` | ArgoCD dashboard |
| `{{VPN_DOMAIN}}` | `vpn.example.com` | Headscale VPN control plane |
| `{{ZULIP_DOMAIN}}` | `messaging.example.com` | Zulip communications (optional) |
| `{{ODOO_DOMAIN}}` | `odoo.example.com` | Odoo ERP (optional) |
| `{{COMPANY_NAME}}` | `My Company` | UI attribution, emails |
| `{{ADMIN_EMAIL}}` | `admin@example.com` | Admin contact |
| `{{YOUR_DOMAIN}}` | `example.com` | Catch-all fallback |

## What Gets Deployed

### Core Infrastructure (~10 services)

| Service | Purpose |
|---------|---------|
| **Orion-LD** (FIWARE) | NGSI-LD Context Broker — single source of truth for all entities |
| **Keycloak** | OIDC/OAuth2 authentication and authorization |
| **PostgreSQL + TimescaleDB** | Relational data + time-series telemetry |
| **MongoDB** | Orion-LD entity registry |
| **MinIO** | S3-compatible object storage (COGs, terrain tiles, module assets) |
| **Redis** | Cache, job queue (Celery/RQ), rate limiting |
| **Mosquitto** | MQTT broker for IoT devices |
| **Traefik** | Ingress controller with automatic TLS via cert-manager |
| **Cert-manager** | Automatic Let's Encrypt certificate issuance and renewal |
| **ArgoCD** | GitOps continuous deployment |

### Modules (16 slots)

| Module | Tier | Category |
|--------|------|----------|
| **Weather + Risks** | Core | Meteorology, 6 risk models (spray, frost, wind, GDD) |
| **Vegetation Prime** | T1 | Satellite indices (NDVI/SAVI/GNDVI/NDRE), crop season analysis |
| **Crop Health Engine** | T1 | 9 engines (CWSI, MDS, WUE…) + 5 epidemiological models |
| **BioOrchestrator** | T2 | Neo4j biological knowledge graph + IkerKeta (25 data connectors) |
| **DataHub** | T1 | Time-series visualization, CSV/Parquet export, AI predictions |
| **AgriEnergy** | T2 | Agrivoltaic orchestration (solar parks × crops) |
| **GIS Routing** | T2 | Machinery path planning, VRA, ISOBUS XML export |
| **LiDAR** | T2 | 3D point cloud visualization, tree detection, PNOA integration |
| **EU Elevation** | T2 | Multi-source terrain (20 DEMs), Copernicus S3 fallback |
| **Carbon** | T1 | RothC soil carbon, GHG accounting, MRV reports |
| **Catastro Spain** | T2 | Spanish cadastre integration, parcel lookup |
| **CUE (SIEX)** | T3 | Spanish RD 1054/2022 compliance, IUWS poller, AutoFirma |
| **N8N** | T2 | Per-tenant automation workflows, Stripe addon |
| **Zulip** | T2 | Team messaging with SSO, IoT alert channels |
| **Odoo ERP** | T2 | ERP with SSO auto-config, energy communities |
| **VPN** | T2 | Zero-trust device networking via Headscale/Tailscale |

### Management & Operations

| Tool | Purpose |
|------|---------|
| **Grafana** | Cluster and application monitoring dashboards |
| **Prometheus** | Metrics collection and alerting |
| **Alertmanager** | Email/webhook alert routing |

## DNS Deep Dive

### Why Subdomains?

Each service gets its own subdomain because:
1. **TLS**: Each subdomain gets its own certificate via cert-manager + Let's Encrypt
2. **Isolation**: Traefik routes by `Host` header — clean, no path conflicts
3. **CORS**: Browsers allow subdomain siblings with explicit Origin headers
4. **Security**: Cookie scoping per subdomain (Keycloak cookies on `auth.`, app on main)

### Minimal Setup (3 domains)

If you're resource-constrained, the minimum viable setup is:

| Record | Points to | Service |
|--------|-----------|---------|
| `example.com` | Server IP | Frontend |
| `api.example.com` | Server IP | API Gateway |
| `auth.example.com` | Server IP | Keycloak |

The other services (MinIO, ArgoCD, VPN) can share the main domain via path-based
routing if you adjust the Traefik Ingress rules manually.

## Troubleshooting

### ArgoCD apps stuck in "Progressing"

```bash
# Check sync status
kubectl get apps -n argocd

# Force refresh an app
kubectl patch app <app-name> -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Check pod status
kubectl get pods -n nekazari
```

### Certificate not issued

```bash
# Check certificate status
kubectl get certificates -A

# Check cert-manager challenges
kubectl get challenges -A

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager
```

### DNS not resolving

```bash
# From the server
nslookup api.example.com
curl -k https://api.example.com/health

# cert-manager needs DNS to be live before issuing certificates.
# If DNS isn't ready yet, cert-manager will retry (exponential backoff).
```

### Out of memory

```bash
# Disable optional modules by deleting their ArgoCD config apps:
kubectl delete app zulip-config -n argocd
kubectl delete app odoo-config -n argocd

# Or scale down heavy deployments:
kubectl scale deploy zulip -n nekazari --replicas=0
kubectl scale deploy odoo-backend -n nekazari --replicas=0
```

### Reset everything

```bash
# Delete all ArgoCD apps
kubectl delete apps --all -n argocd

# Delete nekazari namespace
kubectl delete ns nekazari

# Re-apply root app
kubectl apply -f bootstrap/root-config.yaml
```

## Post-Installation

After the platform is running:

1. **Create admin user**: Access Keycloak at `https://auth.YOUR_DOMAIN/auth` →
   admin console → create user with role `PlatformAdmin`

2. **Configure tenant**: Run `scripts/keycloak-setup-mappers.sh` (see nkz repo)
   to set up the tenant attribute mapper

3. **Enable modules**: Modules are registered in `marketplace_modules` table.
   The platform deploys them automatically as they're configured in ArgoCD.

4. **Set up monitoring**: Grafana dashboards are pre-configured. Access at
   `https://YOUR_DOMAIN/grafana`

5. **Backup strategy**: Configure Velero or native PostgreSQL/MinIO backups.
   See `nkz/docs/operations/backup.md`

## Related Repos

| Repo | Type | Purpose |
|------|------|---------|
| [`nkz-os/nkz`](https://github.com/nkz-os/nkz) | Public | Platform monorepo (source of truth) |
| `nkz-os/gitops-config` | Private | Production config overlays for nkz-os deployment |
| `nkz-os/nkz-module-*` | Public | Individual module repos (15+) |

## License

AGPL-3.0 — Nekazari Platform © [robotika.cloud](https://nekazari.robotika.cloud)
Powered by FIWARE. Licensed under AGPL by robotika.cloud.

Module SDK (`@nekazari/module-kit`) and Platform SDK (`nkz-platform-sdk`)
are Apache-2.0 — third-party modules can use any license.
