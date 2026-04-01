# kubernetes-terraform Runbook

End-to-end process for going from a blank Kubernetes cluster to the current deployed state.

---

## What Gets Deployed

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| MetalLB | `metallb-system` | Assigns real IPs from your LAN pool to `LoadBalancer` services |
| cert-manager | `cert-manager` | Issues and renews TLS certificates via Let's Encrypt (Cloudflare DNS-01) |
| Traefik | `traefik` | Ingress controller — routes external HTTPS traffic into the cluster |
| Longhorn | `longhorn-system` | Distributed block storage — provides `ReadWriteOnce` PVCs for stateful workloads |
| ArgoCD | `argocd` | GitOps controller for declarative app deployments |
| Vault | `vault` | Secrets management — the single source of truth for all cluster secrets |
| External Secrets Operator (ESO) | `external-secrets` | Bridges Vault and Kubernetes — reads secrets from Vault, creates native `Secret` objects |

### Why this order matters

- **MetalLB must be first** — Traefik needs a `LoadBalancer` IP to get external traffic in. Without MetalLB that IP never gets assigned.
- **cert-manager before Traefik** — Traefik's config references cert-manager `Certificate` and `ClusterIssuer` CRDs. The CRDs must exist before Terraform can plan those resources.
- **Vault before ESO ClusterSecretStore** — ESO's `ClusterSecretStore` needs to authenticate to Vault. Vault must be running and configured first.
- **Helm charts before CRD resources** — Helm installs CRDs as part of chart deployment. Resources using those CRDs (IngressRoutes, ClusterIssuers, IPAddressPools, etc.) can't be created until the CRDs exist, which is why a two-step apply is required on a fresh cluster.

---

## Why Apply Happens in Two Steps

On a fresh cluster:

1. `make plan-helm` — targets only `helm_release` resources, installs all charts and their CRDs
2. `make plan` — plans everything including CRD-backed resources (IngressRoutes, ClusterIssuers, etc.) and Vault provider resources

If you tried to do `make plan` from scratch, Terraform would fail because it can't plan resources whose CRD types don't exist yet in the Kubernetes API.

The Makefile auto-discovers all `helm_release` resources in `*.tf` files so `plan-helm` always stays up to date without manual maintenance.

---

## Prerequisites

- Terraform installed locally
- A running Kubernetes cluster with kubeconfig available at `~/.kube/config`
- Cloudflare API tokens with **Zone:DNS:Edit** permission for each DNS zone
- The Vault root token from Phase 2 (saved to 1Password)

---

## One-Time Setup

Create `secrets.auto.tfvars` (this file is gitignored — never commit it):

```hcl
cloudflare_zones = {
  "toastdog.net" = "your-cloudflare-token-here"
}

# Override once you've verified staging certs work
# traefik_cert_issuer = "letsencrypt-prod"
```

Then initialize Terraform:

```bash
terraform init
```

---

## Phase 1 — Deploy Helm Charts

Installs all charts and their CRDs. No Vault token needed since only `helm_release` resources are targeted.

```bash
make plan-helm
make apply
```

**What gets created:** MetalLB, cert-manager, Traefik, Longhorn, ArgoCD, Vault, and ESO Helm releases. Vault pods will start but remain **sealed** — this is normal. You'll see them at `0/1 Ready`.

**Verify:**
```bash
kubectl get pods -n metallb-system
kubectl get pods -n cert-manager
kubectl get pods -n traefik
kubectl get pods -n longhorn-system
kubectl get pods -n argocd
kubectl get pods -n vault        # 0/1 is expected — sealed
kubectl get pods -n external-secrets
```

---

## Phase 2 — Initialize and Unseal Vault (Manual)

Vault ships sealed — it has no knowledge of its master key until you initialize it. Initialization happens once and generates the unseal keys and root token. **These must be saved to 1Password immediately — they cannot be recovered.**

### Initialize

Run init on vault-0 only. Init is cluster-wide, not per-pod.

```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3
```

Save the entire output to 1Password: 5 unseal keys + the root token.

### Initial unseal

Unseal vault-0 fully before touching vault-1 or vault-2. The other pods need vault-0 to be active before they can join the Raft cluster.

```bash
# Unseal vault-0 first (3 of 5 keys required)
kubectl exec -n vault vault-0 -- vault operator unseal <key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <key-3>

# Wait for vault-0 to become active, then unseal vault-1 and vault-2
kubectl exec -n vault vault-1 -- vault operator unseal <key-1>
kubectl exec -n vault vault-1 -- vault operator unseal <key-2>
kubectl exec -n vault vault-1 -- vault operator unseal <key-3>

kubectl exec -n vault vault-2 -- vault operator unseal <key-1>
kubectl exec -n vault vault-2 -- vault operator unseal <key-2>
kubectl exec -n vault vault-2 -- vault operator unseal <key-3>
```

### Create the unseal keys Secret

The auto-unseal CronJob (deployed in Phase 1) reads unseal keys from a Kubernetes Secret every minute. Create it now so future restarts are handled automatically. Use 3 of your 5 keys (any 3 will satisfy the threshold).

```bash
kubectl create secret generic vault-unseal-keys \
  -n vault \
  --from-literal=key1=<key-1> \
  --from-literal=key2=<key-2> \
  --from-literal=key3=<key-3>
```

### Verify

```bash
# Should show Initialized: true, Sealed: false, HA Enabled: true
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=<root-token> vault status

# Should show all 3 pods as voters
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=<root-token> vault operator raft list-peers
```

---

## Phase 3 — Full Apply

With Vault running and unsealed, apply everything: CRD-backed resources (IngressRoutes, ClusterIssuers, MetalLB pool, etc.) and Vault provider resources (KV engine, Kubernetes auth, ESO role/policy, ClusterSecretStore).

The Vault provider authenticates using the `VAULT_TOKEN` environment variable.

```bash
VAULT_TOKEN=<root-token> make plan
VAULT_TOKEN=<root-token> make apply
```

**What gets created:**
- MetalLB `IPAddressPool` and `L2Advertisement`
- cert-manager `ClusterIssuer` (staging + prod) and `Certificate` resources
- Traefik `IngressRoute`, `Middleware`, `TLSStore`, and Authentik `ExternalName` service
- Longhorn `IngressRoute`
- ArgoCD `IngressRoute`
- Vault `IngressRoute`, KV v2 engine, Kubernetes auth method + config + policy + role
- ESO `ClusterSecretStore` pointing to Vault

---

## Verification

```bash
# All services reachable
kubectl get ingressroute -A

# Certificates issued (may take a few minutes)
kubectl get certificate -n traefik

# Vault cluster healthy
kubectl get pods -n vault   # all 3 should be 1/1

# ESO connected to Vault
kubectl get clustersecretstore  # STATUS: Valid, READY: True
```

### End-to-end secret sync test

```bash
# Write a test secret to Vault
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=<root-token> \
  vault kv put secret/test foo=bar

# Create an ExternalSecret
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: test-secret
  namespace: default
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: test-secret
  data:
    - secretKey: foo
      remoteRef:
        key: secret/test
        property: foo
EOF

# Should show SecretSynced
kubectl get externalsecret test-secret

# Should output: bar
kubectl get secret test-secret -o jsonpath='{.data.foo}' | base64 -d

# Clean up
kubectl delete externalsecret test-secret
kubectl delete secret test-secret
```

---

## Day-2 Operations

### Routine apply (no Vault changes)

```bash
VAULT_TOKEN=<root-token> make plan
VAULT_TOKEN=<root-token> make apply
```

The Vault token is always required for `make plan` because the vault provider authenticates at plan time.

### Adding a new service

1. Create `<name>.tf` with the `helm_release` and any CRD resources
2. Add variables to `vars.tf` and values to `terraform.tfvars`
3. The Makefile auto-discovers `helm_release` resources — no Makefile changes needed
4. Run a normal apply

### After a node/pod restart

The auto-unseal CronJob runs every minute and unseals any sealed pods automatically. No manual action needed.

### Switching to production TLS certificates

Once staging certificates are verified working (browser shows invalid cert warning, not a connection error), switch to production:

1. Add to `secrets.auto.tfvars`:
   ```hcl
   traefik_cert_issuer = "letsencrypt-prod"
   ```
2. Delete the existing secret to force immediate reissuance:
   ```bash
   kubectl delete secret wildcard-tls -n traefik
   ```
3. Apply:
   ```bash
   VAULT_TOKEN=<root-token> make plan
   VAULT_TOKEN=<root-token> make apply
   ```
