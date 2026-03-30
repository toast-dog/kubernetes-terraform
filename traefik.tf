resource "helm_release" "traefik" {
  depends_on = [helm_release.cert_manager]

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

# One Certificate resource per entry in var.certificates
# Start with letsencrypt-staging to verify the setup,
# then switch traefik_cert_issuer to letsencrypt-prod once confirmed working
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
