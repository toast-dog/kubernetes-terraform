# Provider configurations only — required_providers versions are in the generated versions.tf
# (sourced from root terragrunt.hcl). Do not add required_providers blocks here.

provider "vault" {
  address = "https://${local.vault_hostname}"
}
