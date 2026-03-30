resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = var.metallb_version
  namespace        = "metallb-system"
  create_namespace = true
  wait             = true
}

resource "kubernetes_manifest" "metallb_ip_pool" {
  depends_on = [helm_release.metallb]

  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "homelab-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.metallb_ip_range]
    }
  }
}

resource "kubernetes_manifest" "metallb_l2_advertisement" {
  depends_on = [helm_release.metallb]

  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "homelab-l2advert"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["homelab-pool"]
    }
  }
}
