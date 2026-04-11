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

# Templated Vault policy — scopes each request to the authenticating pod's own namespace.
# The accessor interpolation is resolved at apply time from vault_auth_backend.kubernetes.
# Adding a new app namespace requires zero Terraform changes — ESO generates a TokenRequest
# for the vault-auth SA in the ExternalSecret's namespace, Vault substitutes that namespace
# into the template, and access is automatically scoped.
resource "vault_policy" "secret_store" {
  name = "secret-store"
  policy = <<-EOT
    path "secret/data/{{identity.entity.aliases.${vault_auth_backend.kubernetes.accessor}.metadata.service_account_namespace}}/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/{{identity.entity.aliases.${vault_auth_backend.kubernetes.accessor}.metadata.service_account_namespace}}/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# Single Vault auth role — bound to the vault-auth SA in any namespace ("*").
# ESO's ClusterSecretStore generates a short-lived TokenRequest for vault-auth in
# the ExternalSecret's namespace; Vault validates it and populates the identity
# metadata that the templated policy above uses for path substitution.
resource "vault_kubernetes_auth_backend_role" "secret_store" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "secret-store"
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = ["*"]
  token_policies                   = [vault_policy.secret_store.name]
  token_ttl                        = 3600
}
