# kubernetes-terraform

Terragrunt configuration for deploying core Kubernetes services.

See [RUNBOOK.md](RUNBOOK.md) for the full process — from a blank cluster to the current deployed state.

## Module Layout

```
core-helm/    Helm releases only: MetalLB, cert-manager, Traefik, Longhorn
core/         CRD-backed resources: IngressRoutes, ClusterIssuers, MetalLB pool, NetworkPolicies
argocd/       ArgoCD Helm release + IngressRoute (depends on core/)
vault-helm/   Vault + ESO Helm releases, unseal CronJob, IngressRoute, NetworkPolicies
vault/        Vault provider resources: KV engine, Kubernetes auth, ESO policies/roles (depends on vault-helm/)
```

Modules are applied in dependency order by Terragrunt. The `*-helm/` split exists because the kubernetes provider validates CRD-backed resources against the live cluster at plan time — CRDs must exist before the paired module can apply.

## Components

### Core

| Component | Namespace | Description |
|-----------|-----------|-------------|
| MetalLB | `metallb-system` | LoadBalancer IP allocation |
| cert-manager | `cert-manager` | TLS certificates via Let's Encrypt (Cloudflare DNS-01) |
| Traefik | `traefik` | Ingress controller with automatic HTTPS |
| Longhorn | `longhorn-system` | Distributed block storage for stateful workloads |
| Vault | `vault` | Secrets management |
| External Secrets Operator | `external-secrets` | Syncs Vault secrets into Kubernetes Secrets |
| ArgoCD | `argocd` | GitOps controller for declarative app deployments |

## Secrets

Create `core/secrets.auto.tfvars` (gitignored):

```hcl
cloudflare_zones = {
  "toastdog.net" = "your-token-here"
}

# Uncomment once staging certs are verified working
# traefik_cert_issuer = "letsencrypt-prod"
```

## Usage

```bash
# Fresh cluster bootstrap
make bootstrap

# After bootstrap: initialize Vault, store unseal keys, wait for CronJob, then:
export VAULT_TOKEN=<root-token>
make bootstrap-vault
```

For day-2 operations, export your Vault token and use the standard plan/apply:

```bash
export VAULT_TOKEN=<root-token>
make plan
make apply
```

The Vault token is required at plan time because the vault provider authenticates against Vault's API to refresh state.

**Tip:** use the 1Password CLI to avoid pasting the token manually:
```bash
export VAULT_TOKEN=$(op environment read <environment id>)
make plan
make apply
```

## Related Repositories

| Repo | Purpose |
|------|---------|
| [kubernetes-apps](https://git.thompson-manor.org/toast-dog/kubernetes-apps) | ArgoCD app-of-apps: CloudNativePG, Authentik, Atlantis |
| [tf-authentik](https://git.thompson-manor.org/toast-dog/tf-authentik) | Authentik provider configuration (providers, outposts, applications, groups) |
