resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = var.longhorn_version
  namespace        = "longhorn-system"
  create_namespace = true
  wait             = true

  values = [templatefile("${path.module}/config/longhorn-values.yaml", {
    longhorn_replica_count = var.longhorn_replica_count
  })]
}
