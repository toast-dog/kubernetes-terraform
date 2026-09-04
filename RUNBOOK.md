# kubernetes-terraform Runbook

End-to-end process for going from a blank Kubernetes cluster to the current deployed state.

---

## What Gets Deployed

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| MetalLB | `metallb-system` | Assigns real IPs from your LAN pool to `LoadBalancer` services |
| cert-manager | `cert-manager` | Issues and renews TLS certificates — Let's Encrypt (Cloudflare DNS-01) for public certs, a self-signed internal CA for internal-only certs |
| Traefik | `traefik` | Ingress controller — routes external HTTPS traffic into the cluster |
| Longhorn | `longhorn-system` | Distributed block storage — provides persistent volumes for stateful workloads |
| External Secrets Operator (ESO) | `external-secrets` | Bridges 1Password and Kubernetes — reads secrets from a 1Password vault via the SDK provider, creates native `Secret` objects |
| trust-manager | `cert-manager` | Propagates the internal CA's public cert to namespaces that need to trust it (currently just `traefik`), staying in sync as the CA renews |
| ArgoCD | `argocd` | GitOps controller for declarative app deployments |

### Why module order matters

- **core-helm before core** — Helm installs CRDs. The kubernetes provider validates CRD-backed resources (IngressRoutes, ClusterIssuers, IPAddressPools) against the live cluster at plan time, so CRDs must exist first. This also means ESO's Helm release lives in `core-helm/` — its `ClusterSecretStore` (a CRD-backed resource) lives in `core/`.
- **MetalLB before Traefik** — Traefik's Helm release needs a `LoadBalancer` IP. Without MetalLB's pool, the IP never gets assigned and Helm's `wait=true` would block indefinitely. Traefik is deployed with `wait=false` and gets its IP once the MetalLB pool is created in the core/ step.
- **trust-manager propagates the internal CA** — `core/internal-ca.tf`'s self-signed root Certificate is issued by cert-manager, then a `Bundle` resource (trust-manager, installed in `core-helm/`) continuously syncs its public cert into the `traefik` namespace. This is a single-pass apply — no wait step needed, since trust-manager's controller reconciles asynchronously and re-syncs automatically whenever cert-manager renews or rotates the CA (see rotationPolicy: Always on the root Certificate).

---

## Module Layout

```
core-helm/    Helm releases: MetalLB, cert-manager, Traefik, Longhorn, External Secrets Operator, trust-manager
core/         CRD resources: IngressRoutes, ClusterIssuers, MetalLB pool, ClusterSecretStore,
              self-signed internal CA, NetworkPolicies
argocd/       ArgoCD Helm release + IngressRoute         (depends on: core)
apps/argocd/  ArgoCD's ExternalSecrets + root app-of-apps (depends on: argocd)
secrets/      Long-lived 1Password items (argocd, authentik) — no dependencies, and
              deliberately excluded from `make wipe-state` (see that module's
              terragrunt.hcl). Not tied to the cluster's lifecycle at all.
```

Terragrunt applies modules in dependency order automatically. `make plan` / `make apply` run all modules; individual modules can be targeted with `cd <module> && terragrunt plan`.

---

## Prerequisites

- Terragrunt installed locally
- A running Kubernetes cluster with kubeconfig at `~/.kube/config`
- Cloudflare API tokens with **Zone:DNS:Edit** permission for each DNS zone
- A 1Password vault dedicated to this cluster's secrets, and a Service Account token scoped read-only to it (see One-Time Setup below)

---

## One-Time Setup

**1Password**: in the 1Password app/web UI, create a vault dedicated to this cluster. Note its UUID (vault "..." menu → Vault Settings) and set it as `onepassword_vault_id` in `root.hcl`.

Under Developer → Service Accounts, create **two**:
- A read+write one, scoped to that vault only. Export its token as `OP_SERVICE_ACCOUNT_TOKEN` before running any `terragrunt`/`make` command — this is what Terraform's own `onepassword` provider authenticates with (never stored in a file; ideally exported via `op read`/`op run` rather than pasted).
- A read-only one, scoped to that vault only. Its token doesn't get exported anywhere — it gets stored as a field value in the `cluster-bootstrap` item below, which Terraform then copies into a runtime Secret for ESO to use in-cluster.

There's no local secrets file — `core/`'s `onepassword` provider reads externally-sourced bootstrap
credentials directly from a `cluster-bootstrap` item (see `core/bootstrap-secrets.tf`), instead of
from `core/secrets.auto.tfvars` on disk. Create that item by hand, once, in the 1Password app/web
UI, with these sections and fields:

| Section | Field | Value |
|---------|-------|-------|
| `cloudflare` | `toastdog.net` (one field per DNS zone, labeled with the zone name) | Cloudflare API token with `Zone:DNS:Edit` permission for that zone |
| `metallb` | `bgp-password` | MD5 auth password for MetalLB↔OPNsense FRR peering — must match `proxmox-terraform/ansible/.secrets/bgp.key`; generate with `openssl rand -base64 32` |
| `external-secrets` | `eso-token` | The read-only Service Account token created above |

---

## Bootstrap

```bash
export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>
make bootstrap
```

A single non-interactive `terragrunt run --all apply` — Terragrunt walks the dependency graph declared in each module's `terragrunt.hcl` (`core` → `core-helm`, `argocd` → `core`, `apps/argocd` → `argocd`) and fully applies each module before its dependents even begin planning, which is what lets CRD-backed resources in later modules validate against a live cluster. `secrets/` has no dependencies and applies independently. No manual staging needed.

**What it applies, in the order Terragrunt resolves it:**

1. `core-helm/` — installs MetalLB, cert-manager, Traefik, Longhorn, External Secrets Operator, trust-manager Helm charts
2. `core/` — restores the wildcard TLS cert backup automatically if one exists at `../wildcard-tls-backup.yaml` (prevents cert-manager from burning a Let's Encrypt rate-limit slot re-issuing on every rebuild; a no-op, no-risk skip on a genuine first-ever build with no backup yet), then applies MetalLB pool, cert-manager ClusterIssuers (bootstrap self-signed issuer + root Certificate), the trust-manager `Bundle` that propagates the CA into `traefik`, Traefik IngressRoutes, the 1Password `ClusterSecretStore`, NetworkPolicies
3. `argocd/` — deploys ArgoCD and its IngressRoute
4. `apps/argocd/` — wires up ArgoCD's `ExternalSecret`s, creates ArgoCD's root app-of-apps (which starts ArgoCD syncing `kubernetes-apps` automatically from here on)
5. `secrets/` (any point — no dependencies) — creates the `argocd` and `authentik` 1Password items if they don't already exist

**Verify Helm charts are running:**
```bash
kubectl get pods -n metallb-system
kubectl get pods -n cert-manager     # cert-manager + trust-manager pods
kubectl get pods -n traefik
kubectl get pods -n longhorn-system
kubectl get pods -n argocd
kubectl get pods -n external-secrets
```

trust-manager may take a few seconds after `core/` applies to sync the CA into `traefik` — confirm with `kubectl get secret internal-ca -n traefik`.

**Install the homelab root CA** (cert-manager's self-signed root, replaces the old Vault-issued one — a one-time step per device, 10-year TTL):

```bash
kubectl get secret internal-ca-root -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > homelab-root-ca.crt

# Linux (Debian/Ubuntu)
sudo cp homelab-root-ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
sudo update-ca-certificates

# Windows: double-click .crt → Install Certificate → Local Machine →
#   Trusted Root Certification Authorities

# macOS: open homelab-root-ca.crt → Keychain Access → set to Always Trust
```

---

## Verification

```bash
# All IngressRoutes registered
kubectl get ingressroute -A

# Certificates issued (may take a few minutes)
kubectl get certificate -n traefik
kubectl get certificate -n cert-manager   # internal-ca-root

# ESO ClusterSecretStore connected to 1Password
kubectl get clustersecretstore onepassword
```

### End-to-end secret sync test

ESO uses a single `ClusterSecretStore` named `onepassword`, backed by the 1Password vault set in `root.hcl`. No per-namespace Terraform changes are needed when adding new namespaces — just reference the `onepassword` store by name.

```bash
# Create a test item in 1Password (web UI/app), vault = the cluster's dedicated vault,
# title "test-item", section "credentials", field "foo" = "bar"

# Create an ExternalSecret referencing the ClusterSecretStore
NAMESPACE=<namespace>
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: test-secret
  namespace: ${NAMESPACE}
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: onepassword
    kind: ClusterSecretStore
  target:
    name: test-secret
  data:
    - secretKey: foo
      remoteRef:
        key: test-item/credentials/foo
EOF

# Should show SecretSynced
kubectl get externalsecret test-secret -n ${NAMESPACE}

# Should output: bar
kubectl get secret test-secret -n ${NAMESPACE} -o jsonpath='{.data.foo}' | base64 -d

# Clean up
kubectl delete externalsecret test-secret -n ${NAMESPACE}
kubectl delete secret test-secret -n ${NAMESPACE}
# (delete the test-item from 1Password too)
```

---

## Day-2 Operations

### Routine plan/apply

The onepassword provider authenticates via the `OP_SERVICE_ACCOUNT_TOKEN` environment variable, so it's always required:

```bash
export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>
make plan
make apply
```

**Tip:** use the 1Password CLI to avoid pasting the token manually:
```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(op read "op://<vault>/<item>/<field>")
make plan
make apply
```

### Adding a new service

1. Create `<name>.tf` in the appropriate module with the `helm_release` and CRD resources
2. If the service needs 1Password-backed secrets, write `ExternalSecret` resources referencing `secretStoreRef: { name: onepassword, kind: ClusterSecretStore }` — no Terraform changes required in `core/`
3. If it needs a new long-lived secret (a generated password, not something manually supplied), add an `onepassword_item` resource to `secrets/` rather than to the app's own module — see `secrets/onepassword.tf` for the pattern (and why: that module's state is deliberately never wiped)
4. Add variables to the module's `vars.tf` and values to `terraform.tfvars`
5. Run a normal apply

### Rebuilding the cluster

`make wipe-state` only clears state for `core-helm`, `core`, `argocd`, and `apps/*` — it deliberately leaves `secrets/` alone. The `argocd` and `authentik` 1Password items aren't tied to any particular cluster instance, so there's nothing to reset there: re-running `make bootstrap` against a freshly rebuilt cluster will find those items already exist and just reuse them (`ignore_changes` means their values are left untouched). Don't run `rm -rf .terraform-state` directly — it would wipe `secrets/` too and risk Terraform creating duplicate 1Password items on the next apply.

### Switching to production TLS certificates

Once staging certificates are verified working (browser shows an invalid cert warning, not a connection error):

1. Set in `core/terraform.tfvars`:
   ```hcl
   traefik_cert_issuer = "letsencrypt-prod"
   ```
2. Delete the existing secret to force immediate reissuance:
   ```bash
   kubectl delete secret wildcard-tls -n traefik
   ```
3. Apply:
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>
   make plan
   make apply
   ```
