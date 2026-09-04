# kubernetes-terraform

Terragrunt configuration for deploying core Kubernetes services.

See [RUNBOOK.md](RUNBOOK.md) for the full process — from a blank cluster to the current deployed state.

## Module Layout

```
core-helm/    Helm releases only: MetalLB, cert-manager, Traefik, Longhorn, External Secrets Operator, trust-manager
core/         CRD-backed resources: IngressRoutes, ClusterIssuers, MetalLB pool, ClusterSecretStore,
              self-signed internal CA, NetworkPolicies
argocd/       ArgoCD Helm release + IngressRoute (depends on core/)
apps/argocd/  ArgoCD's ExternalSecrets + root app-of-apps (depends on argocd/)
secrets/      Long-lived 1Password items — no dependencies, never wiped by `make wipe-state`
```

Modules are applied in dependency order by Terragrunt. The `core-helm`/`core` split exists because the kubernetes provider validates CRD-backed resources against the live cluster at plan time — CRDs must exist before the paired module can apply. `secrets/` is isolated on purpose — see RUNBOOK.md's "Rebuilding the cluster" section.

## Components

### Core

| Component | Namespace | Description |
|-----------|-----------|-------------|
| MetalLB | `metallb-system` | LoadBalancer IP allocation |
| cert-manager | `cert-manager` | TLS certificates — Let's Encrypt (Cloudflare DNS-01) for public certs, self-signed internal CA for internal-only certs |
| Traefik | `traefik` | Ingress controller with automatic HTTPS |
| Longhorn | `longhorn-system` | Distributed block storage for stateful workloads |
| External Secrets Operator | `external-secrets` | Syncs secrets from a dedicated 1Password vault into Kubernetes Secrets |
| ArgoCD | `argocd` | GitOps controller for declarative app deployments |

## Secrets

There's no local secrets file. `core/`'s `onepassword` provider reads a `cluster-bootstrap` item
directly from the vault at plan time (see `core/bootstrap-secrets.tf`) — Cloudflare API tokens,
the MetalLB BGP password, and ESO's read-only Service Account token all live there instead of on
disk. Create that item by hand, once, before the first apply — see RUNBOOK.md's One-Time Setup
section for the exact fields.

Also set `onepassword_vault_id` (the 1Password vault's UUID) in `root.hcl`.

## Usage

```bash
# Fresh cluster bootstrap
export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>
make bootstrap
```

For day-2 operations, export your 1Password Service Account token and use the standard plan/apply:

```bash
export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>
make plan
make apply
```

The token is required at plan time because the onepassword provider authenticates against 1Password's API to refresh state.

**Tip:** use the 1Password CLI to avoid pasting the token manually:
```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(op read "op://<vault>/<item>/<field>")
make plan
make apply
```

## Related Repositories

| Repo | Purpose |
|------|---------|
| [kubernetes-apps](https://git.thompson-manor.org/toast-dog/kubernetes-apps) | ArgoCD app-of-apps: CloudNativePG, Authentik, Atlantis |
| [tf-authentik](https://git.thompson-manor.org/toast-dog/tf-authentik) | Authentik provider configuration (providers, outposts, applications, groups) |
