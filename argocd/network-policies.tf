# NetworkPolicies for the argocd namespace.
# Global policies (DNS egress, default deny) are in core/network-policies.tf.
#
# ARGOCD
#
# Inbound ports 8080: traefik only (UI + gRPC CLI access via ingress)
# Outbound internal:  all traffic within argocd namespace — server, redis, repo-server,
#                     dex, and controllers all communicate extensively with each other
# Outbound port 6443: kubernetes API (deploying resources)
# Outbound port 443:  external git (Forgejo at git.thompson-manor.org) + OIDC
# Outbound port 22:   git over SSH

# Scoped to argocd-server only — redis, repo-server, dex, and controllers have
# no business receiving traffic from Traefik, so they are excluded by podSelector.
resource "kubernetes_manifest" "netpol_argocd_allow_ingress_from_traefik" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-ingress-from-traefik", namespace = "argocd" }
    spec = {
      podSelector = { matchLabels = { "app.kubernetes.io/name" = "argocd-server" } }
      policyTypes = ["Ingress"]
      ingress = [{
        from  = [{ namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = "traefik" } } }]
        ports = [{ port = 8080, protocol = "TCP" }]
      }]
    }
  }
}

# ArgoCD components communicate heavily with each other (server↔redis, server↔repo-server,
# server↔dex, controller↔server). Allow all intra-namespace traffic rather than mapping each pair.
resource "kubernetes_manifest" "netpol_argocd_allow_internal" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-argocd-internal", namespace = "argocd" }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress", "Egress"]
      ingress     = [{ from = [{ podSelector = {} }] }]
      egress      = [{ to = [{ podSelector = {} }] }]
    }
  }
}

# application-controller continuously reconciles live cluster state against git — all
# resource creates, updates, and watches go through the API server. Calico evaluates egress post-DNAT.
resource "kubernetes_manifest" "netpol_argocd_allow_egress_k8s_api" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-k8s-api", namespace = "argocd" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to    = [for ip in var.control_plane_ips : { ipBlock = { cidr = "${ip}/32" } }]
        ports = [{ port = 6443, protocol = "TCP" }]
      }]
    }
  }
}

# repo-server fetches git repos over HTTPS or SSH. Port 443 also covers OIDC token
# exchange if ArgoCD SSO is wired to Authentik later.
resource "kubernetes_manifest" "netpol_argocd_allow_egress_external" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-external", namespace = "argocd" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to = [{
          ipBlock = {
            cidr = "0.0.0.0/0"
            except = [
              var.cluster_cidr,
              "10.96.0.0/12",
              "192.168.0.0/16"
            ]
          }
        }]
        ports = [
          { port = 443, protocol = "TCP" }, # git repos + OIDC
          { port = 22, protocol = "TCP" }   # git over SSH
        ]
      }]
    }
  }
}
