# ---------------------------------------------------------------------------
# Shared — injected by root.hcl
# ---------------------------------------------------------------------------

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "domain" {
  type = string
}

variable "control_plane_ips" {
  type = list(string)
}

variable "cluster_cidr" {
  type = string
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

# ---------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------

variable "external_secrets_version" {
  type = string
}

variable "vault_secret_stores" {
  description = "Namespaces to provision with a vault-auth service account and SecretStore."
  type        = list(string)
  default     = []
}
