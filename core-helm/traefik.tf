# MetalLB IPAddressPool/L2Advertisement are configured in core/ (applied after this module).
# wait = false because Helm blocks on LoadBalancer IP assignment, which requires the pool
# from core/. MetalLB assigns the IP automatically once core/ configures the pool.
resource "helm_release" "traefik" {
  depends_on = [helm_release.metallb]

  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_version
  namespace        = "traefik"
  create_namespace = true
  wait             = false

  values = [templatefile("${path.module}/config/traefik-values.yaml", {
    load_balancer_ip = var.traefik_load_balancer_ip
  })]
}
