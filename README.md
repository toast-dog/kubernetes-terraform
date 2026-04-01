# kubernetes-terraform

Terraform configuration for deploying core Kubernetes services.

See [RUNBOOK.md](RUNBOOK.md) for the full process — from a blank cluster to the current deployed state.

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

### Additions

| Component | Namespace | Description |
|-----------|-----------|-------------|
| ArgoCD | `argocd` | GitOps controller for declarative app deployments |

## Secrets

Create `secrets.auto.tfvars` (gitignored):

```hcl
cloudflare_zones = {
  "toastdog.net" = "your-token-here"
}

# Uncomment once staging certs are verified working
# traefik_cert_issuer = "letsencrypt-prod"
```

## Usage

```bash
terraform init

# Step 1: install Helm charts and their CRDs
make plan-helm
make apply

# Step 2: initialize and unseal Vault manually (see RUNBOOK.md)

# Step 3: apply everything else
VAULT_TOKEN=<root-token> make plan
VAULT_TOKEN=<root-token> make apply
```

On subsequent runs a single `make plan && make apply` is sufficient (with `VAULT_TOKEN` set).

## Adding a new component

1. Create `<name>.tf` with the `helm_release` and any CRD resources
2. Add variables to `vars.tf` and values to `terraform.tfvars`
3. The Makefile auto-discovers `helm_release` resources — no Makefile changes needed
