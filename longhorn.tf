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

# Longhorn UI IngressRoute with Authentik forward auth
resource "kubernetes_manifest" "longhorn_ingressroute" {
  depends_on = [helm_release.longhorn, kubernetes_manifest.authentik_middleware]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "longhorn"
      namespace = "longhorn-system"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          kind     = "Rule"
          match    = "Host(`${var.longhorn_hostname}`)"
          priority = 10
          middlewares = [{
            name      = "authentik"
            namespace = "traefik"
          }]
          services = [{
            name = "longhorn-frontend"
            port = 80
          }]
        },
        {
          kind     = "Rule"
          match    = "Host(`${var.longhorn_hostname}`) && PathPrefix(`/outpost.goauthentik.io/`)"
          priority = 15
          services = [{
            name = "authentik-external"
            port = 443
          }]
        }
      ]
    }
  }
}
