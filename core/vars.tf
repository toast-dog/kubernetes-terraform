# ---------------------------------------------------------------------------
# MetalLB
# ---------------------------------------------------------------------------

variable "metallb_ip_range" {
  description = "IP range for MetalLB to assign to LoadBalancer services"
  type        = string
}

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------

variable "acme_email" {
  description = "Email address for Let's Encrypt account registration"
  type        = string
}

variable "cloudflare_zones" {
  description = "Map of Cloudflare zone roots to API tokens with Zone:DNS:Edit permission"
  type        = map(string)
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Traefik
# ---------------------------------------------------------------------------

variable "traefik_cert_issuer" {
  description = "ClusterIssuer to use for all certificates (letsencrypt-staging or letsencrypt-prod)"
  type        = string
}

variable "traefik_default_certificate" {
  description = "Key from the local.certificates map to use as the default TLS certificate"
  type        = string
}
