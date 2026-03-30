# MetalLB
metallb_version  = "0.15.3"  # renovate: datasource=helm registryUrl=https://metallb.github.io/metallb depName=metallb
metallb_ip_range = "192.168.30.160-192.168.30.170"

# cert-manager
cert_manager_version = "1.20.0"  # renovate: datasource=helm registryUrl=oci://quay.io/jetstack/charts depName=cert-manager
acme_email           = "admin@toastdog.net"

# Traefik
traefik_version          = "39.0.6"  # renovate: datasource=helm registryUrl=https://traefik.github.io/charts depName=traefik
traefik_load_balancer_ip = "192.168.30.160"
traefik_cert_issuer      = "letsencrypt-staging" # override to letsencrypt-prod in secrets.auto.tfvars once verified

traefik_default_certificate = "lab-wildcard"

certificates = {
  "lab-wildcard" = {
    domains     = ["*.lab.toastdog.net", "lab.toastdog.net"]
    secret_name = "wildcard-tls"
  }
}
