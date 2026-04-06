# ---------------------------------------------------------------------------
# Shared — injected by root.hcl
# ---------------------------------------------------------------------------

variable "domain" {
  description = "Base domain for all services. Hostnames derived as <service>.<domain> in locals.tf."
  type        = string
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "control_plane_ips" {
  type = list(string)
}

variable "cluster_cidr" {
  type = string
}

# ---------------------------------------------------------------------------
# External Secrets — per-namespace SecretStores
# ---------------------------------------------------------------------------

variable "vault_secret_stores" {
  description = "Namespaces to provision with a scoped Vault policy and Kubernetes auth role. Must match vault_secret_stores in vault-helm/."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

variable "bootstrap_mode" {
  description = "Injected via TF_VAR_bootstrap_mode from the Makefile bootstrap-vault target. Reserved for future Vault PKI work — will toggle provider config (e.g. ca_cert_file) when Vault issues its own TLS cert rather than relying on Let's Encrypt via Traefik."
  type        = bool
  default     = false
}
