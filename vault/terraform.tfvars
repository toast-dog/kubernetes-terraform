# ---------------------------------------------------------------------------
# External Secrets — per-namespace SecretStores
# ---------------------------------------------------------------------------

# Add a namespace here to provision it with a scoped Vault policy and Kubernetes auth role.
# Must match vault_secret_stores in vault-helm/terraform.tfvars.
vault_secret_stores = []

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

# bootstrap_mode is injected via TF_VAR_bootstrap_mode from the Makefile bootstrap-vault
# target. It is reserved for future Vault PKI work (toggling CA cert config once Vault
# issues its own TLS cert). Default is false for normal applies.

