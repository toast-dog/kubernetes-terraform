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

# ArgoCD UI and CLI IngressRoute
# Placed in the argocd namespace per the official ArgoCD + Traefik docs.
# Two routes: HTTP UI (priority 10) and gRPC for the CLI (priority 11, h2c scheme).
# ArgoCD's own authentication protects access; no Authentik middleware needed.
resource "kubernetes_manifest" "argocd_ingressroute" {
  depends_on = [helm_release.argocd]

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
