resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_version
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
}

# ClusterSecretStore — single cluster-wide store backed by Vault.
# serviceAccountRef.name = "vault-auth" with no namespace causes ESO to generate a
# TokenRequest for vault-auth in the ExternalSecret's own namespace. Vault validates
# the token, extracts the service_account_namespace from the JWT, and the templated
# policy in vault/vault.tf scopes access to that namespace automatically.
# Adding a new app requires only: create vault-auth SA in the app namespace (via its
# own Helm chart or ArgoCD Application) and write ExternalSecret resources — no Terraform.
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
        vault = merge(
          {
            server  = var.bootstrap_mode ? "http://vault.vault.svc.cluster.local:8200" : "https://vault.vault.svc.cluster.local:8200"
            path    = "secret"
            version = "v2"
            auth = {
              kubernetes = {
                mountPath = "kubernetes"
                role      = "secret-store"
                # namespace intentionally omitted — ESO generates a TokenRequest for
                # vault-auth in the ExternalSecret's own namespace. Vault sees that
                # namespace in the JWT metadata, and the templated policy scopes access
                # to secret/data/<that-namespace>/* automatically.
                serviceAccountRef = {
                  name = "vault-auth"
                }
              }
            }
          },
          # caProvider references vault-internal-ca in the external-secrets namespace,
          # created by vault/vault_pki.tf. ESO reads it at runtime.
          var.bootstrap_mode ? {} : {
            caProvider = {
              type      = "Secret"
              name      = "vault-internal-ca"
              namespace = "external-secrets"
              key       = "ca.crt"
            }
          }
        )
      }
    }
  }
}
