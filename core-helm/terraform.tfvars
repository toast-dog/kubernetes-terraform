metallb_version = "0.15.3"  # renovate: datasource=helm registryUrl=https://metallb.github.io/metallb depName=metallb

cert_manager_version = "1.20.0"  # renovate: datasource=helm registryUrl=oci://quay.io/jetstack/charts depName=cert-manager

traefik_version          = "39.0.6"  # renovate: datasource=helm registryUrl=https://traefik.github.io/charts depName=traefik
traefik_load_balancer_ip = "192.168.30.160"

longhorn_version       = "1.11.1"  # renovate: datasource=helm registryUrl=https://charts.longhorn.io depName=longhorn
longhorn_replica_count = 3
