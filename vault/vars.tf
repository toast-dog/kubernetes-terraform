# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

variable "bootstrap_mode" {
  description = "Injected via TF_VAR_bootstrap_mode from the Makefile bootstrap-vault target. Reserved for future Vault PKI work — will toggle provider config (e.g. ca_cert_file) when Vault issues its own TLS cert rather than relying on Let's Encrypt via Traefik."
  type        = bool
  default     = false
}
