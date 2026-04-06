# Helm release is in core-helm/ — CRDs are guaranteed to exist when this module runs.

resource "kubernetes_manifest" "metallb_ip_pool" {
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
