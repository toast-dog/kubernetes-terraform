# kubernetes-terraform Runbook

End-to-end process for going from a blank Kubernetes cluster to the current deployed state.

---

## What Gets Deployed

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| MetalLB | `metallb-system` | Assigns real IPs from your LAN pool to `LoadBalancer` services |
| cert-manager | `cert-manager` | Issues and renews TLS certificates via Let's Encrypt (Cloudflare DNS-01) |
| Traefik | `traefik` | Ingress controller — routes external HTTPS traffic into the cluster |
| Longhorn | `longhorn-system` | Distributed block storage — provides persistent volumes for stateful workloads |
| Vault | `vault` | Secrets management — the single source of truth for all cluster secrets |
| External Secrets Operator (ESO) | `external-secrets` | Bridges Vault and Kubernetes — reads secrets from Vault, creates native `Secret` objects |
| ArgoCD | `argocd` | GitOps controller for declarative app deployments |

### Why module order matters

- **core-helm before core** — Helm installs CRDs. The kubernetes provider validates CRD-backed resources (IngressRoutes, ClusterIssuers, IPAddressPools) against the live cluster at plan time, so CRDs must exist first.
- **MetalLB before Traefik** — Traefik's Helm release needs a `LoadBalancer` IP. Without MetalLB's pool, the IP never gets assigned and Helm's `wait=true` would block indefinitely. Traefik is deployed with `wait=false` and gets its IP once the MetalLB pool is created in the core/ step.
- **vault-helm before vault** — The Vault provider authenticates against Vault's API at plan time. Vault must be deployed, initialized, and unsealed before vault/ can apply.
- **Longhorn before Vault** — Vault HA runs 3 pods, each storing the Raft database on a PVC. Longhorn provides those PVCs with replication across nodes.

---

## Module Layout

```
core-helm/    Helm releases: MetalLB, cert-manager, Traefik, Longhorn
core/         CRD resources: IngressRoutes, ClusterIssuers, MetalLB pool, NetworkPolicies
argocd/       ArgoCD Helm release + IngressRoute         (depends on: core)
vault-helm/   Vault + ESO Helm releases, unseal CronJob  (depends on: core)
vault/        Vault provider resources: KV, auth, ESO    (depends on: vault-helm)
```

Terragrunt applies modules in dependency order automatically. `make plan` / `make apply` run all modules; individual modules can be targeted with `cd <module> && terragrunt plan`.

---

## Prerequisites

- Terragrunt installed locally
- A running Kubernetes cluster with kubeconfig at `~/.kube/config`
- Cloudflare API tokens with **Zone:DNS:Edit** permission for each DNS zone

---

## One-Time Setup

Create `core/secrets.auto.tfvars` (gitignored — never commit it). A template is at `core/secrets.auto.tfvars.example`:

```hcl
cloudflare_zones = {
  "toastdog.net" = "your-cloudflare-token-here"
}

# BGP authentication password for MetalLB <-> OPNsense FRR peering (TCP MD5)
# Must match proxmox-terraform/ansible/.secrets/bgp.key
metallb_bgp_password = "your-bgp-password-here"  # generate with: openssl rand -base64 32

# Uncomment once staging certs are verified working
# traefik_cert_issuer = "letsencrypt-prod"
```

---

## Phase 1 — Bootstrap the Cluster

Runs all automated steps in order. Prompts once for confirmation, then pauses to let you restore the wildcard TLS cert backup (avoids burning a Let's Encrypt rate limit).

```bash
make bootstrap
```

**What it does (in order):**

1. `core-helm/` — installs MetalLB, cert-manager, Traefik, Longhorn Helm charts
2. Pauses — prompts you to restore the wildcard TLS cert backup:
   ```bash
   kubectl apply -f ../wildcard-tls-backup.yaml
   ```
   Skip this step on a first-ever build. Restoring the backup prevents cert-manager from issuing a new cert (5/week Let's Encrypt rate limit).
3. `core/` — applies MetalLB pool, cert-manager ClusterIssuers, Traefik IngressRoutes, NetworkPolicies
4. `argocd/` — deploys ArgoCD and its IngressRoute
5. `vault-helm/` — deploys Vault, ESO, the unseal CronJob, and the Vault IngressRoute

After step 5, Vault pods will start but remain **sealed** — this is expected.

**Verify Helm charts are running:**
```bash
kubectl get pods -n metallb-system
kubectl get pods -n cert-manager
kubectl get pods -n traefik
kubectl get pods -n longhorn-system
kubectl get pods -n argocd
kubectl get pods -n vault           # 0/1 expected — sealed
kubectl get pods -n external-secrets
```

---

## Phase 2 — Initialize and Unseal Vault (Manual)

Vault ships sealed — it has no knowledge of its master key until initialized. Initialization happens once and generates the unseal keys and root token. **Save these to 1Password immediately — they cannot be recovered.**

### Initialize

```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 -key-threshold=3 -format=json > vault-init.json
```

`vault-init.json` is gitignored. Open it and save the unseal keys and root token to 1Password.

### Store unseal keys

The auto-unseal CronJob (deployed in Phase 1) reads keys from this Secret every minute. Create it now so future restarts are handled automatically.

```bash
kubectl create secret generic vault-unseal-keys -n vault \
  --from-literal=key1=$(jq -r '.unseal_keys_b64[0]' vault-init.json) \
  --from-literal=key2=$(jq -r '.unseal_keys_b64[1]' vault-init.json) \
  --from-literal=key3=$(jq -r '.unseal_keys_b64[2]' vault-init.json)
```

### Wait for auto-unseal

The CronJob runs every minute and unseals all pods. After about a minute:

```bash
kubectl get pods -n vault   # all 3 should become 1/1
```

### Export the root token

```bash
export VAULT_TOKEN=$(jq -r '.root_token' vault-init.json)
```

### About the auto-unseal CronJob

The CronJob approach has a security trade-off: unseal keys live in a Kubernetes Secret (base64 in etcd). Anyone with sufficient RBAC or etcd access can read them. Acceptable for a homelab; not appropriate for production.

**Proper alternatives:**

| Option | How it works | Best for |
|--------|-------------|----------|
| **Cloud KMS** | Vault calls AWS KMS / GCP Cloud KMS / Azure Key Vault to unwrap the master key on startup | Environments with a cloud provider |
| **Transit Vault** | A second small Vault instance holds the unseal key for the primary via the Transit secrets engine | Air-gapped or on-prem |
| **HSM** | The master key never leaves dedicated hardware | High-security on-prem |

**Migrating to auto-unseal (e.g. cloud KMS):**
1. Create a KMS key in your cloud provider.
2. Add a `seal` stanza to `vault-values.yaml` pointing to the key.
3. While Vault is running and unsealed, run `vault operator migrate` — re-encrypts the master key without downtime or data loss.
4. Delete the `vault-unseal-keys` Secret and remove the CronJob from `vault-helm/kubernetes.tf`.
5. Restart Vault pods — they unseal automatically via KMS.

---

## Phase 3 — Vault PKI + TLS Bootstrap

With `VAULT_TOKEN` exported, run:

```bash
make bootstrap-vault
```

This runs four steps automatically, with a wait between each:

**Step [1/4] — vault Apply 1 (`bootstrap_mode=true`)**

Configures Vault internals and sets up the PKI CA:
- KV v2 secrets engine at `secret/`
- Kubernetes auth method + config (allows pods to authenticate using their service account tokens)
- Root CA (`pki` mount, 10-year) and Intermediate CA (`pki_int` mount, 5-year)
- ACME protocol enabled on `pki_int` (for future Proxmox/OPNsense cert issuance)
- cert-manager `vault-internal` ClusterIssuer (pointing to Vault HTTP at this stage)
- `vault-tls` Certificate resource — cert-manager issues it immediately via the ClusterIssuer

**Step [2/4] — Wait for `vault-tls` Secret**

Polls until cert-manager has issued the `vault-tls` Secret in the vault namespace (~30s). This secret contains the TLS cert and key that Vault pods will use.

**Step [3/4] — vault-helm Apply 2 (enables Vault TLS)**

- Switches Vault's listener from HTTP to HTTPS (mounts the `vault-tls` Secret into pods)
- Updates the IngressRoute to proxy HTTPS to Vault via the homelab CA (`ServersTransport`)
- Updates the unseal CronJob to connect over HTTPS
- Deletes all Vault pods (OnDelete update strategy) — they restart with TLS enabled
- Waits up to 5 minutes for the unseal CronJob to re-unseal all pods
- Waits for Vault to accept authenticated requests via the ingress before proceeding

**Step [4/4] — vault Apply 2**

- Switches the `vault-internal` ClusterIssuer from HTTP to HTTPS + caBundle
- Creates `vault-internal-ca` Secrets in each configured namespace (used by ESO `SecretStore` resources to verify Vault's TLS cert)

**After bootstrap-vault completes — install the homelab root CA**

Vault is now the cluster's internal CA. Export the root cert and add it to your trust stores:

```bash
# Export root CA
curl -s https://vault.lab.toastdog.net/v1/pki/ca/pem > homelab-root-ca.crt

# Linux (Debian/Ubuntu)
sudo cp homelab-root-ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
sudo update-ca-certificates

# Windows: double-click .crt → Install Certificate → Local Machine →
#   Trusted Root Certification Authorities

# macOS: open homelab-root-ca.crt → Keychain Access → set to Always Trust
```

This is a one-time step per device. The root CA has a 10-year TTL so it won't need to be reinstalled.

---

## Verification

```bash
# All IngressRoutes registered
kubectl get ingressroute -A

# Certificates issued (may take a few minutes)
kubectl get certificate -n traefik

# Vault cluster healthy
kubectl get pods -n vault        # all 3 should be 1/1

# ESO ClusterSecretStore connected to Vault
kubectl get clustersecretstore
```

### End-to-end secret sync test

ESO uses a single `ClusterSecretStore` named `vault`. The only per-namespace requirement is a `vault-auth` ServiceAccount (which app Helm charts or ArgoCD Applications create). No Terraform changes are needed when adding new namespaces.

```bash
# Write a test secret to Vault
NAMESPACE=<namespace>
kubectl exec -n vault vault-0 -- sh -c \
  "VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt VAULT_TOKEN=$VAULT_TOKEN \
   vault kv put secret/${NAMESPACE}/test foo=bar"

# Create the vault-auth SA ESO will use to authenticate
kubectl create serviceaccount vault-auth -n ${NAMESPACE}

# Create an ExternalSecret referencing the ClusterSecretStore
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: test-secret
  namespace: ${NAMESPACE}
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
        key: ${NAMESPACE}/test
        property: foo
EOF

# Should show SecretSynced
kubectl get externalsecret test-secret -n ${NAMESPACE}

# Should output: bar
kubectl get secret test-secret -n ${NAMESPACE} -o jsonpath='{.data.foo}' | base64 -d

# Clean up
kubectl delete externalsecret test-secret -n ${NAMESPACE}
kubectl delete secret test-secret -n ${NAMESPACE}
kubectl delete serviceaccount vault-auth -n ${NAMESPACE}
```

---

## Day-2 Operations

### Routine plan/apply

The vault provider authenticates against Vault's API at plan time, so `VAULT_TOKEN` is always required:

```bash
export VAULT_TOKEN=<root-token>
make plan
make apply
```

**Tip:** use the 1Password CLI to avoid pasting the token manually:
```bash
export VAULT_TOKEN=$(op environment read <environment id>)
make plan
make apply
```

### Adding a new service

1. Create `<name>.tf` in the appropriate module with the `helm_release` and CRD resources
2. If the service needs Vault secrets, ensure it creates a `vault-auth` ServiceAccount in its namespace — no Terraform changes required
3. Add variables to the module's `vars.tf` and values to `terraform.tfvars`
4. Run a normal apply

### After a node/pod restart

The auto-unseal CronJob runs every minute and unseals any sealed pods automatically. No manual action needed.

### Switching to production TLS certificates

Once staging certificates are verified working (browser shows an invalid cert warning, not a connection error):

1. Add to `core/secrets.auto.tfvars`:
   ```hcl
   traefik_cert_issuer = "letsencrypt-prod"
   ```
2. Delete the existing secret to force immediate reissuance:
   ```bash
   kubectl delete secret wildcard-tls -n traefik
   ```
3. Apply:
   ```bash
   export VAULT_TOKEN=<root-token>
   make plan
   make apply
   ```
