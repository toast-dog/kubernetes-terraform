# ---------------------------------------------------------------------------
# Bootstrap workflow — first apply on a fresh cluster:
#
#   1. Set bootstrap_mode = true in terraform.tfvars
#   2. Apply vault-helm/ (deploys Vault + ESO, CronJob, NetworkPolicies)
#   3. Initialize Vault and store unseal keys (see Makefile bootstrap target)
#   4. Wait for the vault-unseal CronJob to unseal all pods (~1 min)
#   5. Set VAULT_TOKEN to the root token from vault-init.json
#   6. terragrunt apply  (this module) → vault_* resources succeed
#   7. Implement Vault PKI (VAULT_PKI_PLAN.md), then set bootstrap_mode = false
# ---------------------------------------------------------------------------

# KV v2 secrets engine — all secrets stored under secret/
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

# Kubernetes auth method — allows pods to authenticate using their service account tokens
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

# Kubernetes API host for token validation — CA cert is auto-discovered from the pod's mounted service account
resource "vault_kubernetes_auth_backend_config" "default" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc.cluster.local:443"
}

# Per-namespace Vault policies — each grants read access only to that namespace's secret path.
# Driven by var.vault_secret_stores; add a namespace there to provision it automatically.
resource "vault_policy" "secret_store" {
  for_each = toset(var.vault_secret_stores)
  name     = "secret-store-${each.key}"
  policy   = <<-EOT
    path "secret/data/${each.key}/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/${each.key}/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# Per-namespace Vault auth roles — each binds to the vault-auth service account
# in the app namespace. ESO uses the TokenRequest API to generate short-lived
# tokens for that SA, so the central ESO service account never touches Vault directly.
resource "vault_kubernetes_auth_backend_role" "secret_store" {
  for_each                         = toset(var.vault_secret_stores)
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "secret-store-${each.key}"
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = [each.key]
  token_policies                   = [vault_policy.secret_store[each.key].name]
  token_ttl                        = 3600
}
