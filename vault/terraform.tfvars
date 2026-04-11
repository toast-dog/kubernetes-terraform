# bootstrap_mode is injected via TF_VAR_bootstrap_mode from the Makefile bootstrap-vault
# target. It toggles Vault TLS (HTTP vs HTTPS) and ClusterIssuer config during initial setup.
# Default is false for normal applies.
