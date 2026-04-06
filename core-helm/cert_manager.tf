resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  # Install CRDs as part of the Helm release so they upgrade automatically alongside the chart
  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]
}
