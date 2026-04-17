# Helm release is in core-helm/ — CRDs and namespace are guaranteed to exist when this module runs.

# One Certificate per entry in local.certificates
resource "kubernetes_manifest" "certificates" {
  for_each = local.certificates

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
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "authentik"
      namespace = "traefik"
    }
    spec = {
      forwardAuth = {
        address            = "http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik"
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

# Traefik dashboard IngressRoute with Authentik forward auth
resource "kubernetes_manifest" "traefik_dashboard" {
  depends_on = [kubernetes_manifest.authentik_middleware]

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
          match    = "Host(`${local.traefik_dashboard_host}`)"
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
          match    = "Host(`${local.traefik_dashboard_host}`) && PathPrefix(`/outpost.goauthentik.io/`)"
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

# Set the default TLS certificate for all Traefik entrypoints
resource "kubernetes_manifest" "default_tls_store" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "TLSStore"
    metadata = {
      name      = "default"
      namespace = "traefik"
    }
    spec = {
      defaultCertificate = {
        secretName = local.certificates[var.traefik_default_certificate].secret_name
      }
    }
  }
}
