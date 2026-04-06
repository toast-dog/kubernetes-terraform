# ---------------------------------------------------------------------------
# Shared — injected by root.hcl
# ---------------------------------------------------------------------------

variable "domain" {
  description = "Base domain for all services (e.g. lab.toastdog.net). Hostnames are derived as <service>.<domain> in locals.tf."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "control_plane_ips" {
  description = "List of control plane node IPs — used in NetworkPolicy egress rules to allow API server access"
  type        = list(string)
}

variable "cluster_cidr" {
  description = "Pod CIDR for the cluster — used in webhook ingress rules"
  type        = string
}

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

variable "external_authentik_url" {
  description = "Base URL of the external Authentik instance (e.g. https://auth.example.com)"
  type        = string
}

variable "traefik_cert_issuer" {
  description = "ClusterIssuer to use for all certificates (letsencrypt-staging or letsencrypt-prod)"
  type        = string
}

variable "traefik_default_certificate" {
  description = "Key from the local.certificates map to use as the default TLS certificate"
  type        = string
}
