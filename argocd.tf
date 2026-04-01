resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  values = [templatefile("${path.module}/config/argocd-values.yaml", {
    argocd_hostname = var.argocd_hostname
  })]
}

# Two routes: UI (priority 10) and gRPC CLI (priority 11, h2c) — ArgoCD handles its own auth, no Authentik needed
resource "kubernetes_manifest" "argocd_ingressroute" {
  depends_on = [helm_release.argocd, helm_release.traefik]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "argocd"
      namespace = "argocd"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          kind     = "Rule"
          match    = "Host(`${var.argocd_hostname}`)"
          priority = 10
          services = [{
            name = "argocd-server"
            port = 80
          }]
        },
        {
          kind     = "Rule"
          match    = "Host(`${var.argocd_hostname}`) && Header(`Content-Type`, `application/grpc`)"
          priority = 11
          services = [{
            name   = "argocd-server"
            port   = 80
            scheme = "h2c"
          }]
        }
      ]
    }
  }
}
