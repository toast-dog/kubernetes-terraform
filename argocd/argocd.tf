resource "helm_release" "argocd" {
  # core/ (MetalLB, Traefik) ordering is enforced by the Terragrunt dependency
  # block in terragrunt.hcl — no cross-module depends_on needed here.

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  values = [templatefile("${path.module}/config/argocd-values.yaml", {
    argocd_hostname    = local.argocd_hostname
    authentik_hostname = local.authentik_hostname
  })]
}

# Two routes: UI (priority 10) and gRPC CLI (priority 11, h2c) — ArgoCD handles its own auth, no Authentik needed
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
          match    = "Host(`${local.argocd_hostname}`)"
          priority = 10
          services = [{
            name = "argocd-server"
            port = 80
          }]
        },
        {
          kind     = "Rule"
          match    = "Host(`${local.argocd_hostname}`) && Header(`Content-Type`, `application/grpc`)"
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
