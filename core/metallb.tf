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

resource "kubernetes_manifest" "metallb_bgp_peer" {
  manifest = {
    apiVersion = "metallb.io/v1beta2"
    kind       = "BGPPeer"
    metadata = {
      name      = "opnsense"
      namespace = "metallb-system"
    }
    spec = {
      peerAddress = "192.168.30.1"
      peerASN     = 64512
      myASN       = 64513
    }
  }
}

resource "kubernetes_manifest" "metallb_bgp_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "BGPAdvertisement"
    metadata = {
      name      = "homelab-bgp"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["homelab-pool"]
    }
  }
}
