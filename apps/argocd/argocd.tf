# vault-auth SA — ESO generates a TokenRequest for this SA; Vault's ACL template
# scopes access to secret/data/argocd/* based on the namespace in the JWT.
resource "kubernetes_service_account_v1" "vault_auth" {
  metadata {
    name      = "vault-auth"
    namespace = "argocd"
  }
}

resource "kubernetes_manifest" "argocd_admin_secret" {
  depends_on = [vault_kv_secret_v2.argocd]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-admin-password"
      namespace = "argocd"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "argocd-secret"
        creationPolicy = "Merge"
      }
      data = [{
        secretKey = "admin.password"
        remoteRef = {
          key      = "argocd/config"
          property = "admin-password-hash"
        }
      }]
    }
  }
}
