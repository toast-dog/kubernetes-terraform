metallb_version = "0.15.3"  # renovate: datasource=helm registryUrl=https://metallb.github.io/metallb depName=metallb

cert_manager_version = "v1.20.1"  # renovate: datasource=docker depName=quay.io/jetstack/charts/cert-manager

traefik_version          = "39.0.7"  # renovate: datasource=helm registryUrl=https://traefik.github.io/charts depName=traefik
traefik_load_balancer_ip = "192.168.30.160"

longhorn_version       = "1.11.1"  # renovate: datasource=helm registryUrl=https://charts.longhorn.io depName=longhorn
longhorn_replica_count = 3
