# Hostnames derived from var.domain — use local.* instead of var.* for these.

locals {
  argocd_hostname    = "argocd.${var.domain}"
  authentik_hostname = "auth.${var.domain}"
}
