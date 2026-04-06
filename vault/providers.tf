# Provider configurations only — required_providers versions are in the generated
# versions.tf (sourced from root.hcl, which declares all providers including vault).

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# Vault is always accessed via the Traefik IngressRoute (HTTPS), even before Vault PKI.
# bootstrap_mode is reserved for future Vault PKI work (e.g. toggling ca_cert_file
# when Vault issues its own TLS cert instead of relying on Let's Encrypt via Traefik).
provider "vault" {
  address = "https://${local.vault_hostname}"
}
