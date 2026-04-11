resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_version
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
}

# Per-namespace vault-auth service accounts — ESO uses the TokenRequest API to generate
# short-lived tokens. Each SA authenticates to Vault with a namespace-scoped role only.
# The namespace must already exist before applying (created by Helm or ArgoCD).
resource "kubernetes_service_account_v1" "vault_auth" {
  for_each   = toset(var.vault_secret_stores)
  depends_on = [helm_release.external_secrets]

  metadata {
    name      = "vault-auth"
    namespace = each.key
  }
}

# Per-namespace SecretStores — namespace-scoped, so an ExternalSecret in one
# namespace cannot reference another namespace's store. References the local
# vault-auth SA; no cross-namespace credential sharing.
resource "kubernetes_manifest" "vault_secret_store" {
  for_each   = toset(var.vault_secret_stores)
  depends_on = [helm_release.external_secrets, kubernetes_service_account_v1.vault_auth]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata = {
      name      = "vault"
      namespace = each.key
    }
    spec = {
      provider = {
        vault = merge(
          {
            server  = var.bootstrap_mode ? "http://vault.vault.svc.cluster.local:8200" : "https://vault.vault.svc.cluster.local:8200"
            path    = "secret"
            version = "v2"
            auth = {
              kubernetes = {
                mountPath = "kubernetes"
                role      = "secret-store-${each.key}"
                serviceAccountRef = {
                  name = "vault-auth"
                }
              }
            }
          },
          # caProvider references the vault-internal-ca Secret created by vault/vault_pki.tf.
          # ESO reads it at runtime — no Terraform cross-module output needed.
          var.bootstrap_mode ? {} : {
            caProvider = {
              type = "Secret"
              name = "vault-internal-ca"
              key  = "ca.crt"
            }
          }
        )
      }
    }
  }
}
