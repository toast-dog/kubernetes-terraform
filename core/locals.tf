# Hostnames and derived values computed from var.domain.
# Use local.* instead of var.* for any value that includes the domain name.

locals {
  traefik_dashboard_host = "traefik.${var.domain}"
  longhorn_hostname       = "longhorn.${var.domain}"

  # Certificate map — domains interpolated from var.domain so they stay consistent
  certificates = {
    "lab-wildcard" = {
      domains     = ["*.${var.domain}", var.domain]
      secret_name = "wildcard-tls"
    }
  }
}
