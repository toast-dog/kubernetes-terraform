metallb_version = "0.16.1"  # renovate: datasource=helm registryUrl=https://metallb.github.io/metallb depName=metallb

cert_manager_version = "v1.21.0"  # renovate: datasource=docker depName=quay.io/jetstack/charts/cert-manager

traefik_version          = "41.0.1"  # renovate: datasource=helm registryUrl=https://traefik.github.io/charts depName=traefik
traefik_load_balancer_ip = "192.168.30.160"

longhorn_version       = "1.12.0"  # renovate: datasource=helm registryUrl=https://charts.longhorn.io depName=longhorn
longhorn_replica_count = 3
