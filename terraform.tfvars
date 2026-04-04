# ---------------------------------------------------------------------------
# MetalLB
# ---------------------------------------------------------------------------

metallb_version  = "0.15.3"  # renovate: datasource=helm registryUrl=https://metallb.github.io/metallb depName=metallb
metallb_ip_range = "192.168.30.160-192.168.30.170"

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------

cert_manager_version = "1.20.0"  # renovate: datasource=helm registryUrl=oci://quay.io/jetstack/charts depName=cert-manager
acme_email           = "admin@toastdog.net"

# ---------------------------------------------------------------------------
# Traefik
# ---------------------------------------------------------------------------

traefik_version          = "39.0.6"  # renovate: datasource=helm registryUrl=https://traefik.github.io/charts depName=traefik
traefik_load_balancer_ip = "192.168.30.160"
traefik_dashboard_host   = "traefik.lab.toastdog.net"
external_authentik_url   = "https://auth.thompson-manor.com"
traefik_cert_issuer      = "letsencrypt-prod"
traefik_default_certificate = "lab-wildcard"

certificates = {
  "lab-wildcard" = {
    domains     = ["*.lab.toastdog.net", "lab.toastdog.net"]
    secret_name = "wildcard-tls"
  }
}

# ---------------------------------------------------------------------------
# Longhorn
# ---------------------------------------------------------------------------

longhorn_version       = "1.11.1"  # renovate: datasource=helm registryUrl=https://charts.longhorn.io depName=longhorn
longhorn_hostname      = "longhorn.lab.toastdog.net"
longhorn_replica_count = 3

# ---------------------------------------------------------------------------
# Vault
# ---------------------------------------------------------------------------

vault_version  = "0.32.0"  # renovate: datasource=helm registryUrl=https://helm.releases.hashicorp.com depName=vault
vault_hostname = "vault.lab.toastdog.net"

# ---------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------

external_secrets_version = "2.2.0"  # renovate: datasource=helm registryUrl=https://charts.external-secrets.io depName=external-secrets

# ---------------------------------------------------------------------------
# ArgoCD
# ---------------------------------------------------------------------------

argocd_version  = "9.4.17"  # renovate: datasource=helm registryUrl=https://argoproj.github.io/argo-helm depName=argo-cd
argocd_hostname = "argocd.lab.toastdog.net"
