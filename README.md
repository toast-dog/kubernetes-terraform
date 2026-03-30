# kubernetes-terraform

Terraform configuration for deploying core Kubernetes services.

## Components

| Component | Description |
|-----------|-------------|
| `metallb` | LoadBalancer IP allocation |
| `cert_manager` | Certificate management via Let's Encrypt (Cloudflare DNS-01) |
| `traefik` | Ingress controller with automatic HTTPS |

## Prerequisites

- Terraform installed locally
- A running Kubernetes cluster (provisioned by cluster-bootstrap)
- kubeconfig available locally (fetched automatically by cluster-bootstrap)
- Cloudflare API token with **Zone:DNS:Edit** permission

## Secrets

Create `secrets.auto.tfvars` (gitignored) with your sensitive values:

```hcl
cloudflare_zones = {
  "example.com"    = "your-token-here"
  # "example2.com" = "another-token-here"
}
```

Each entry is a Cloudflare zone root mapped to an API token with **Zone:DNS:Edit** permission for that zone. cert-manager will use longest-suffix matching to route DNS-01 challenges to the correct token.

When you're ready to switch from staging to production certificates, add the override here too (see [TLS / Certificates](#tls--certificates)):

```hcl
traefik_cert_issuer = "letsencrypt-prod"
```

## Usage

On a fresh cluster the Helm chart CRDs don't exist yet, so a two-step apply is required:

```bash
terraform init

# Step 1: install Helm charts and their CRDs
make plan-helm
make apply

# Step 2: apply everything else (ClusterIssuers, Certificates, etc.)
make plan
make apply
```

On subsequent runs a single `make plan && make apply` is sufficient.

## TLS / Certificates

Certificates default to `letsencrypt-staging` to avoid Let's Encrypt rate limits while testing. Once you've verified HTTPS is working (browser will show an invalid cert warning with staging), switch to production by adding to `secrets.auto.tfvars`:

```hcl
traefik_cert_issuer = "letsencrypt-prod"
```

Then delete the existing secret to force immediate reissuance and apply:

```bash
kubectl delete secret wildcard-tls -n traefik
make plan && make apply
```

## Configuration

| Variable | Description |
|----------|-------------|
| `metallb_version` | MetalLB Helm chart version |
| `metallb_ip_range` | IP range for LoadBalancer services |
| `cert_manager_version` | cert-manager Helm chart version |
| `acme_email` | Email for Let's Encrypt account registration |
| `cloudflare_zones` | Map of Cloudflare zone roots to API tokens (sensitive, set in `secrets.auto.tfvars`) |
| `traefik_version` | Traefik Helm chart version |
| `traefik_domains` | Domains to include in the wildcard certificate |
| `traefik_load_balancer_ip` | Fixed IP from the MetalLB pool assigned to Traefik |
| `traefik_cert_issuer` | ClusterIssuer to use (`letsencrypt-staging` or `letsencrypt-prod`) |
| `kubeconfig_path` | Path to kubeconfig (default: `~/.kube/config`) |

## Adding a new component

1. Create a `<name>.tf` in the root with the `helm_release` and any CRD resources
2. Add variables to `vars.tf` and values to `terraform.tfvars`
3. The Makefile will automatically pick up the new Helm release for `make plan-helm`
