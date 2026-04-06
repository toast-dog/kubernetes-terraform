# Hostnames derived from var.domain — use local.* instead of var.* for these.

locals {
  vault_hostname = "vault.${var.domain}"
}
