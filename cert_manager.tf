resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  # Install cert-manager's Custom Resource Definitions (CRDs) — the Kubernetes API extensions
  # that define resources like Certificate, ClusterIssuer, etc. — as part of the Helm release
  # so they are managed and upgraded automatically alongside the chart
  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]
}

# One secret per Cloudflare zone, named cloudflare-token-<zone> (dots replaced with dashes)
resource "kubernetes_secret_v1" "cloudflare_api_tokens" {
  for_each   = toset(nonsensitive(keys(var.cloudflare_zones)))
  depends_on = [helm_release.cert_manager]

  metadata {
    name      = "cloudflare-token-${replace(each.key, ".", "-")}"
    namespace = "cert-manager"
  }

  data = {
    api-token = var.cloudflare_zones[each.key]
  }
}

resource "kubernetes_manifest" "cluster_issuer_staging" {
  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.cloudflare_api_tokens]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-staging"
        }
        solvers = [for zone in nonsensitive(keys(var.cloudflare_zones)) : {
          selector = {
            dnsZones = [zone]
          }
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = {
                name = "cloudflare-token-${replace(zone, ".", "-")}"
                key  = "api-token"
              }
            }
          }
        }]
      }
    }
  }
}

resource "kubernetes_manifest" "cluster_issuer_prod" {
  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.cloudflare_api_tokens]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [for zone in nonsensitive(keys(var.cloudflare_zones)) : {
          selector = {
            dnsZones = [zone]
          }
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = {
                name = "cloudflare-token-${replace(zone, ".", "-")}"
                key  = "api-token"
              }
            }
          }
        }]
      }
    }
  }
}
