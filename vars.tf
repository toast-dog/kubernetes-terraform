variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

# ---------------------------------------------------------------------------
# MetalLB
# ---------------------------------------------------------------------------

variable "metallb_version" {
  type = string
}

variable "metallb_ip_range" {
  description = "IP range for MetalLB to assign to LoadBalancer services"
  type        = string
}

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------

variable "cert_manager_version" {
  type = string
}

variable "acme_email" {
  description = "Email address for Let's Encrypt account registration"
  type        = string
}

variable "cloudflare_zones" {
  description = "Map of Cloudflare zone roots to API tokens with Zone:DNS:Edit permission (e.g. { \"toastdog.net\" = \"token...\" })"
  type        = map(string)
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Traefik
# ---------------------------------------------------------------------------

variable "traefik_version" {
  type = string
}

variable "traefik_load_balancer_ip" {
  description = "Fixed IP from the MetalLB pool to assign to the Traefik LoadBalancer service"
  type        = string
}

variable "traefik_dashboard_host" {
  description = "Hostname for the Traefik dashboard (e.g. traefik.lab.toastdog.net)"
  type        = string
}

variable "external_authentik_url" {
  description = "Base URL of the external Authentik instance (e.g. https://auth.example.com)"
  type        = string
}

variable "traefik_cert_issuer" {
  description = "ClusterIssuer to use for all certificates (letsencrypt-staging or letsencrypt-prod)"
  type        = string
  default     = "letsencrypt-staging"
}

variable "certificates" {
  description = "Map of certificates to issue. Each entry defines the DNS names and the Kubernetes secret name to store the cert in."
  type = map(object({
    domains     = list(string)
    secret_name = string
  }))
}

variable "traefik_default_certificate" {
  description = "Key from the certificates map to use as the default TLS certificate for all Traefik entrypoints"
  type        = string

  validation {
    condition     = contains(keys(var.certificates), var.traefik_default_certificate)
    error_message = "traefik_default_certificate must be a key in the certificates map."
  }
}

# ---------------------------------------------------------------------------
# Longhorn
# ---------------------------------------------------------------------------

variable "longhorn_version" {
  type = string
}

variable "longhorn_hostname" {
  description = "Hostname for the Longhorn UI (e.g. longhorn.lab.toastdog.net)"
  type        = string
}

variable "longhorn_replica_count" {
  description = "Number of Longhorn volume replicas — should match the number of worker nodes"
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# Vault
# ---------------------------------------------------------------------------

variable "vault_version" {
  type = string
}

variable "vault_image_tag" {
  description = "Vault container image tag for the unseal CronJob — should match the app version deployed by the Helm chart"
  type        = string
}

variable "vault_hostname" {
  description = "Hostname for the Vault UI (e.g. vault.lab.toastdog.net)"
  type        = string
}

# ---------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------

variable "external_secrets_version" {
  type = string
}

# ---------------------------------------------------------------------------
# ArgoCD
# ---------------------------------------------------------------------------

variable "argocd_version" {
  type = string
}

variable "argocd_hostname" {
  description = "Hostname for the ArgoCD UI (e.g. argocd.lab.toastdog.net)"
  type        = string
}
