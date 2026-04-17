# Helm release is in core-helm/ — namespace is guaranteed to exist when this module runs.

# Longhorn UI IngressRoute with Authentik forward auth
resource "kubernetes_manifest" "longhorn_ingressroute" {
  depends_on = [kubernetes_manifest.authentik_middleware]

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
          match    = "Host(`${local.longhorn_hostname}`)"
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
          match    = "Host(`${local.longhorn_hostname}`) && PathPrefix(`/outpost.goauthentik.io/`)"
          priority = 15
          services = [{
            name      = "authentik-server"
            namespace = "authentik"
            port      = 80
          }]
        }
      ]
    }
  }
}
