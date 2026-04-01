resource "helm_release" "external_secrets" {
  depends_on = [helm_release.vault]

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_version
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
}

# ClusterSecretStore — available to ExternalSecret resources in any namespace.
# Connects to Vault via internal cluster DNS using Kubernetes auth.
resource "kubernetes_manifest" "vault_cluster_secret_store" {
  depends_on = [helm_release.external_secrets]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "vault"
    }
    spec = {
      provider = {
        vault = {
          server  = "http://vault.vault.svc.cluster.local:8200"
          path    = "secret"
          version = "v2"
          auth = {
            kubernetes = {
              mountPath = "kubernetes"
              role      = "external-secrets"
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }
}
