# restricted — ArgoCD chart sets proper security contexts on all containers
resource "kubernetes_labels" "namespace_argocd" {
  depends_on  = [helm_release.argocd]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "argocd"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
    "network-policy"                     = "managed"
  }
}
