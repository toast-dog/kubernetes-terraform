# Pod Security Standards (PSS) labels for vault and external-secrets namespaces.

# baseline — vault server pods only set allowPrivilegeEscalation: false; missing capabilities.drop: ALL
# and seccompProfile, both required for restricted. The Helm chart doesn't expose these as values.
resource "kubernetes_labels" "namespace_vault" {
  depends_on  = [helm_release.vault]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "vault"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "baseline"
    "pod-security.kubernetes.io/warn"    = "baseline"
    "network-policy"                     = "managed"
  }
}

# restricted — ESO chart sets proper security contexts on all containers
resource "kubernetes_labels" "namespace_external_secrets" {
  depends_on  = [helm_release.external_secrets]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "external-secrets"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
    "network-policy"                     = "managed"
  }
}
