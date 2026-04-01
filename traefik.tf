resource "helm_release" "traefik" {
  depends_on = [helm_release.cert_manager, kubernetes_manifest.metallb_ip_pool, kubernetes_manifest.metallb_l2_advertisement]

  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_version
  namespace        = "traefik"
  create_namespace = true
  wait             = true

  values = [templatefile("${path.module}/config/traefik-values.yaml", {
    load_balancer_ip = var.traefik_load_balancer_ip
  })]
}

# One Certificate per entry in var.certificates — defaults to letsencrypt-staging, override in secrets.auto.tfvars once verified
resource "kubernetes_manifest" "certificates" {
  for_each   = var.certificates
  depends_on = [helm_release.traefik]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = each.key
      namespace = "traefik"
    }
    spec = {
      secretName = each.value.secret_name
      issuerRef = {
        name = var.traefik_cert_issuer
        kind = "ClusterIssuer"
      }
      dnsNames = each.value.domains
    }
  }
}

# ForwardAuth middleware that delegates authentication to Authentik
resource "kubernetes_manifest" "authentik_middleware" {
  depends_on = [helm_release.traefik]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "authentik"
      namespace = "traefik"
    }
    spec = {
      forwardAuth = {
        address            = "${var.external_authentik_url}/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader = true
        authResponseHeaders = [
          "X-authentik-username",
          "X-authentik-groups",
          "X-authentik-entitlements",
          "X-authentik-email",
          "X-authentik-name",
          "X-authentik-uid",
          "X-authentik-jwt",
          "X-authentik-meta-jwks",
          "X-authentik-meta-outpost",
          "X-authentik-meta-provider",
          "X-authentik-meta-app",
          "X-authentik-meta-version",
        ]
      }
    }
  }
}

# ExternalName service so Traefik can route outpost callbacks to the external Authentik instance
resource "kubernetes_service_v1" "authentik_external" {
  depends_on = [helm_release.traefik]

  metadata {
    name      = "authentik-external"
    namespace = "traefik"
  }

  spec {
    type          = "ExternalName"
    external_name = replace(var.external_authentik_url, "https://", "")
  }
}

# Traefik dashboard IngressRoute with Authentik forward auth
resource "kubernetes_manifest" "traefik_dashboard" {
  depends_on = [helm_release.traefik, kubernetes_manifest.authentik_middleware]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          kind     = "Rule"
          match    = "Host(`${var.traefik_dashboard_host}`)"
          priority = 10
          middlewares = [{
            name      = "authentik"
            namespace = "traefik"
          }]
          services = [{
            name = "api@internal"
            kind = "TraefikService"
          }]
        },
        {
          kind     = "Rule"
          match    = "Host(`${var.traefik_dashboard_host}`) && PathPrefix(`/outpost.goauthentik.io/`)"
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

# Set the default TLS certificate for all Traefik entrypoints
resource "kubernetes_manifest" "default_tls_store" {
  depends_on = [helm_release.traefik]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "TLSStore"
    metadata = {
      name      = "default"
      namespace = "traefik"
    }
    spec = {
      defaultCertificate = {
        secretName = var.certificates[var.traefik_default_certificate].secret_name
      }
    }
  }
}
