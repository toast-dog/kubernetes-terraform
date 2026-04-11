# NetworkPolicies — default-deny-all per namespace, with explicit allow rules on top.
#
# Without any NetworkPolicy, every pod can freely reach every other pod across all
# namespaces. Adding ANY policy to a namespace switches it to deny-by-default for
# the traffic types (Ingress/Egress) that policy covers. The pattern used here:
#   1. One Calico GlobalNetworkPolicy for DNS egress across all managed namespaces
#   2. One Calico GlobalNetworkPolicy for default deny across all managed namespaces
#   3. Per-namespace Kubernetes NetworkPolicies for each specific traffic flow
#
# Managed namespaces are identified by the label: network-policy=managed
# Adding this label to a new namespace automatically applies both global policies.
#
# Calico (the cluster CNI) enforces these rules at the node level using iptables.
#
# Cluster addressing (referenced in ipBlock rules below):
#   Pod CIDR:     var.cluster_cidr  (10.244.0.0/16)
#   Service CIDR: 10.96.0.0/12  — kubernetes API reachable at 10.96.0.1:443
#   Node CIDR:    192.168.30.0/24 — control plane on .150
#
# Webhook ingress note:
#   kube-apiserver uses hostNetwork and calls webhook pods via Calico IPIP tunnels.
#   By the time the packet arrives at the destination pod, the source IP is the
#   control plane's tunl0 address (within the pod CIDR), not the node IP.
#   ipBlock with namespaceSelector cannot match hostNetwork pods. Using cluster_cidr
#   as the ipBlock source is the correct approach — a secondary defense is that
#   webhook servers require valid kube-apiserver TLS client certs, so network
#   access alone is not sufficient to make a valid webhook call.

# ===========================================================================
# DNS EGRESS — single GlobalNetworkPolicy for all managed namespaces
#
# Applies to any namespace labelled network-policy=managed. Uses order 500
# so it is evaluated before the default deny (order 10000).
# ===========================================================================

resource "kubernetes_manifest" "global_allow_dns" {
  manifest = {
    apiVersion = "projectcalico.org/v3"
    kind       = "GlobalNetworkPolicy"
    metadata   = { name = "allow-dns-egress" }
    spec = {
      order             = 500
      namespaceSelector = "network-policy == 'managed'"
      selector          = "all()"
      types             = ["Egress"]
      egress = [
        {
          action   = "Allow"
          protocol = "UDP"
          destination = {
            namespaceSelector = "kubernetes.io/metadata.name == 'kube-system'"
            ports             = [53]
          }
        },
        {
          action   = "Allow"
          protocol = "TCP"
          destination = {
            namespaceSelector = "kubernetes.io/metadata.name == 'kube-system'"
            ports             = [53]
          }
        }
      ]
    }
  }
}

# Denies all traffic not explicitly allowed by a Kubernetes NetworkPolicy.
# Scoped to managed namespaces via network-policy=managed label — system namespaces
# (kube-system, calico-system, etc.) are unaffected.
# order 10000 — evaluated last, after all allow rules.
resource "kubernetes_manifest" "global_default_deny" {
  manifest = {
    apiVersion = "projectcalico.org/v3"
    kind       = "GlobalNetworkPolicy"
    metadata   = { name = "default-deny-managed-namespaces" }
    spec = {
      order             = 10000
      namespaceSelector = "network-policy == 'managed'"
      selector          = "all()"
      types             = ["Ingress", "Egress"]
      ingress           = [{ action = "Deny" }]
      egress            = [{ action = "Deny" }]
    }
  }
}

# ===========================================================================
# CERT-MANAGER
#
# Inbound port 10250: kube-apiserver webhook calls (Certificate/Issuer validation)
# Outbound port 6443: kubernetes API (managing certificate secrets)
# Outbound port 443:  internet (Let's Encrypt ACME API, Cloudflare DNS API for DNS-01)
#
# Webhook note: same IPIP/tunl0 reason as documented in the file header.
# The external egress rule explicitly excludes internal CIDRs so cert-manager
# cannot reach cluster-internal services through the broad external rule.
# ===========================================================================

resource "kubernetes_manifest" "netpol_cert_manager_allow_ingress_webhook" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-ingress-webhook", namespace = "cert-manager" }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [{
        from  = [{ ipBlock = { cidr = var.cluster_cidr } }]
        ports = [{ port = 10250, protocol = "TCP" }]
      }]
    }
  }
}

resource "kubernetes_manifest" "netpol_cert_manager_allow_egress_k8s_api" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-k8s-api", namespace = "cert-manager" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to    = [for ip in var.control_plane_ips : { ipBlock = { cidr = "${ip}/32" } }]
        ports = [{ port = 6443, protocol = "TCP" }]
      }]
    }
  }
}

# cert-manager authenticates to Vault (k8s auth) and calls the PKI sign endpoint to issue
# internal certificates. Vault runs in the vault namespace on port 8200.
resource "kubernetes_manifest" "netpol_cert_manager_allow_egress_vault" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-vault", namespace = "cert-manager" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to    = [{ namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = "vault" } } }]
        ports = [{ port = 8200, protocol = "TCP" }]
      }]
    }
  }
}

# Reaches Let's Encrypt (ACME) and Cloudflare (DNS-01 challenge) on the public internet.
# Internal CIDRs are excluded so this broad rule can't be used to reach cluster services.
resource "kubernetes_manifest" "netpol_cert_manager_allow_egress_external" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-external", namespace = "cert-manager" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to = [{
          ipBlock = {
            cidr = "0.0.0.0/0"
            except = [
              var.cluster_cidr,   # pod CIDR — cert-manager shouldn't reach pods via external rule
              "10.96.0.0/12",     # service CIDR — covered by the k8s-api rule above
              "192.168.0.0/16"    # RFC1918 LAN
            ]
          }
        }]
        ports = [{ port = 443, protocol = "TCP" }]
      }]
    }
  }
}

# ===========================================================================
# TRAEFIK
#
# Inbound ports 8000/8443: anywhere (it is the public ingress — must accept external traffic)
# Outbound to cluster:     pod CIDR + service CIDR, all ports — Traefik routes to arbitrary
#                          backends and resolves service endpoints directly to pod IPs;
#                          per-namespace ingress policies control what is actually accepted
# Outbound port 443:       internet only (Authentik ForwardAuth at auth.thompson-manor.com)
# ===========================================================================

resource "kubernetes_manifest" "netpol_traefik_allow_ingress_public" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-ingress-public", namespace = "traefik" }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [{
        ports = [{ port = 8000, protocol = "TCP" }, { port = 8443, protocol = "TCP" }]
        # no `from` block = allow from anywhere
      }]
    }
  }
}

# Traefik watches IngressRoute/Ingress resources and reads TLS secrets from the API server.
# Calico evaluates egress post-DNAT: kubernetes.default.svc:443 → control-plane-node:6443.
resource "kubernetes_manifest" "netpol_traefik_allow_egress_k8s_api" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-k8s-api", namespace = "traefik" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to    = [for ip in var.control_plane_ips : { ipBlock = { cidr = "${ip}/32" } }]
        ports = [{ port = 6443, protocol = "TCP" }]
      }]
    }
  }
}

resource "kubernetes_manifest" "netpol_traefik_allow_egress_cluster" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-cluster-backends", namespace = "traefik" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        # No port restriction — Traefik is the ingress controller and routes to backends
        # on varying ports. Each destination namespace enforces its own ingress policy.
        to = [
          { ipBlock = { cidr = var.cluster_cidr } }, # pod CIDR
          { ipBlock = { cidr = "10.96.0.0/12" } }    # service CIDR
        ]
      }]
    }
  }
}

resource "kubernetes_manifest" "netpol_traefik_allow_egress_external" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-external", namespace = "traefik" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to = [{
          ipBlock = {
            cidr = "0.0.0.0/0"
            except = [
              var.cluster_cidr,  # pod CIDR — covered by the cluster-backends rule
              "10.96.0.0/12",    # service CIDR — covered by the cluster-backends rule
              "192.168.0.0/16"   # RFC1918 LAN
            ]
          }
        }]
        ports = [{ port = 443, protocol = "TCP" }] # Authentik ForwardAuth
      }]
    }
  }
}

# ===========================================================================
# METALLB
#
# Note: the speaker DaemonSet uses hostNetwork: true, which places it on the
# node's network interface rather than the pod network. NetworkPolicies only
# apply to pod-network traffic, so speaker pods are outside their scope —
# L2 ARP advertisement traffic is not affected by these policies.
#
# The controller pod (not the speaker) runs on the pod network and needs:
# Inbound port 9443:  kube-apiserver webhook calls (IPAddressPool/L2Advertisement validation)
# Outbound port 6443: kubernetes API (watching services, updating status)
#
# Webhook note: same IPIP/tunl0 reason as documented in the file header.
# ===========================================================================

resource "kubernetes_manifest" "netpol_metallb_allow_ingress_webhook" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-ingress-webhook", namespace = "metallb-system" }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [{
        from  = [{ ipBlock = { cidr = var.cluster_cidr } }]
        ports = [{ port = 9443, protocol = "TCP" }]
      }]
    }
  }
}

# Controller and speaker coordinate IP assignment over the pod network.
resource "kubernetes_manifest" "netpol_metallb_allow_internal" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-metallb-internal", namespace = "metallb-system" }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress", "Egress"]
      ingress     = [{ from = [{ podSelector = {} }] }]
      egress      = [{ to = [{ podSelector = {} }] }]
    }
  }
}

# Controller watches for LoadBalancer Services and updates their status with the
# assigned IP — both the watch and status writes go through the API server. Calico evaluates egress post-DNAT.
resource "kubernetes_manifest" "netpol_metallb_allow_egress_k8s_api" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-k8s-api", namespace = "metallb-system" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to    = [for ip in var.control_plane_ips : { ipBlock = { cidr = "${ip}/32" } }]
        ports = [{ port = 6443, protocol = "TCP" }]
      }]
    }
  }
}

# ===========================================================================
# LONGHORN
#
# Longhorn is intentionally excluded from NetworkPolicy management. The
# attachdetach-controller in kube-controller-manager calls longhorn-backend:9500
# from the control plane host network — outside the pod network and unreachable
# via NetworkPolicy rules. Restricting longhorn-system causes volume attach
# failures on cluster startup.
# ===========================================================================
