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

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

variable "bootstrap_mode" {
  description = "Set true only during initial cluster bootstrap before Vault PKI is available. Controls Vault TLS listener (vault-values.yaml), ESO SecretStore addresses, and unseal CronJob protocol. Default false — only set via TF_VAR_bootstrap_mode during first-time setup."
  type        = bool
  default     = false
}
