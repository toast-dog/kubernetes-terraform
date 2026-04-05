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
# VAULT
#
# Inbound port 8200: external-secrets (secret reads), traefik (UI), vault namespace (unseal)
# Inbound port 8201: vault namespace only (raft replication between vault-0/1/2)
# Outbound port 6443: kubernetes API (vault k8s auth method validates pod service account tokens)
# ===========================================================================

# Allows vault pods to talk to each other (raft replication on 8201) and the
# unseal CronJob pods to reach vault servers (8200). The unseal pod labels change
# per-run (batch job name is time-based), so we select all pods in the namespace.
resource "kubernetes_manifest" "netpol_vault_allow_internal" {
  depends_on = [helm_release.vault]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-vault-internal", namespace = "vault" }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress", "Egress"]
      ingress     = [{ from = [{ podSelector = {} }] }]
      egress      = [{ to = [{ podSelector = {} }] }]
    }
  }
}

resource "kubernetes_manifest" "netpol_vault_allow_ingress_8200" {
  depends_on = [helm_release.vault, helm_release.external_secrets, helm_release.traefik]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-ingress-8200", namespace = "vault" }
    spec = {
      podSelector = { matchLabels = { "app.kubernetes.io/name" = "vault" } }
      policyTypes = ["Ingress"]
      ingress = [{
        from = [{
          namespaceSelector = {
            matchExpressions = [{
              key      = "kubernetes.io/metadata.name"
              operator = "In"
              values   = ["external-secrets", "traefik"]
            }]
          }
        }]
        ports = [{ port = 8200, protocol = "TCP" }]
      }]
    }
  }
}

# Vault's k8s auth method calls the API server to validate pod service account tokens.
# Calico evaluates egress post-DNAT: kubernetes.default.svc:443 → control-plane-node:6443.
resource "kubernetes_manifest" "netpol_vault_allow_egress_k8s_api" {
  depends_on = [helm_release.vault]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-k8s-api", namespace = "vault" }
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
# EXTERNAL-SECRETS
#
# Inbound port 10250: kube-apiserver webhook calls (ExternalSecret/SecretStore validation)
# Outbound port 8200: vault (reading secrets)
# Outbound port 6443: kubernetes API (creating/updating Kubernetes Secrets)
#
# Webhook note: ipBlock cidr = cluster_cidr because kube-apiserver webhook calls
# traverse Calico IPIP — the source IP at the pod is the control plane tunl0
# address (within pod CIDR), not the node IP. See file header for full explanation.
# ===========================================================================

resource "kubernetes_manifest" "netpol_external_secrets_allow_ingress_webhook" {
  depends_on = [helm_release.external_secrets]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-ingress-webhook", namespace = "external-secrets" }
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

# ESO reads secrets from Vault to sync into Kubernetes Secrets. Mirrors the
# allow-ingress-8200 rule on the vault side — both ends of the connection need a policy.
# namespaceSelector is sufficient — Calico evaluates post-DNAT so it sees vault pod IPs.
resource "kubernetes_manifest" "netpol_external_secrets_allow_egress_vault" {
  depends_on = [helm_release.external_secrets, helm_release.vault]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-vault", namespace = "external-secrets" }
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

# ESO writes synced secrets to the API server and watches ExternalSecret/ClusterSecretStore
# resources via a long-lived watch connection. Calico evaluates egress post-DNAT.
resource "kubernetes_manifest" "netpol_external_secrets_allow_egress_k8s_api" {
  depends_on = [helm_release.external_secrets]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-k8s-api", namespace = "external-secrets" }
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
# CERT-MANAGER
#
# Inbound port 10250: kube-apiserver webhook calls (Certificate/Issuer validation)
# Outbound port 6443: kubernetes API (managing certificate secrets)
# Outbound port 443:  internet (Let's Encrypt ACME API, Cloudflare DNS API for DNS-01)
#
# Webhook note: same IPIP/tunl0 reason as external-secrets above.
# The external egress rule explicitly excludes internal CIDRs so cert-manager
# cannot reach cluster-internal services through the broad external rule.
# ===========================================================================

resource "kubernetes_manifest" "netpol_cert_manager_allow_ingress_webhook" {
  depends_on = [helm_release.cert_manager]
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
  depends_on = [helm_release.cert_manager]
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

# Reaches Let's Encrypt (ACME) and Cloudflare (DNS-01 challenge) on the public internet.
# Internal CIDRs are excluded so this broad rule can't be used to reach cluster services.
resource "kubernetes_manifest" "netpol_cert_manager_allow_egress_external" {
  depends_on = [helm_release.cert_manager]
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
  depends_on = [helm_release.traefik]
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
  depends_on = [helm_release.traefik]
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
  depends_on = [helm_release.traefik]
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
  depends_on = [helm_release.traefik]
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
# ARGOCD
#
# Inbound ports 8080: traefik only (UI + gRPC CLI access via ingress)
# Outbound internal:  all traffic within argocd namespace — server, redis, repo-server,
#                     dex, and controllers all communicate extensively with each other
# Outbound port 6443: kubernetes API (deploying resources)
# Outbound port 443:  external git (Forgejo at git.thompson-manor.org) + OIDC
# Outbound port 22:   git over SSH
# ===========================================================================

# Scoped to argocd-server only — redis, repo-server, dex, and controllers have
# no business receiving traffic from Traefik, so they are excluded by podSelector.
resource "kubernetes_manifest" "netpol_argocd_allow_ingress_from_traefik" {
  depends_on = [helm_release.argocd, helm_release.traefik]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-ingress-from-traefik", namespace = "argocd" }
    spec = {
      podSelector = { matchLabels = { "app.kubernetes.io/name" = "argocd-server" } }
      policyTypes = ["Ingress"]
      ingress = [{
        from  = [{ namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = "traefik" } } }]
        ports = [{ port = 8080, protocol = "TCP" }]
      }]
    }
  }
}

# ArgoCD components communicate heavily with each other (server↔redis, server↔repo-server,
# server↔dex, controller↔server). Allow all intra-namespace traffic rather than mapping each pair.
resource "kubernetes_manifest" "netpol_argocd_allow_internal" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-argocd-internal", namespace = "argocd" }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress", "Egress"]
      ingress     = [{ from = [{ podSelector = {} }] }]
      egress      = [{ to = [{ podSelector = {} }] }]
    }
  }
}

# application-controller continuously reconciles live cluster state against git — all
# resource creates, updates, and watches go through the API server. Calico evaluates egress post-DNAT.
resource "kubernetes_manifest" "netpol_argocd_allow_egress_k8s_api" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-k8s-api", namespace = "argocd" }
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

# repo-server fetches git repos over HTTPS or SSH. Port 443 also covers OIDC token
# exchange if ArgoCD SSO is wired to Authentik later.
resource "kubernetes_manifest" "netpol_argocd_allow_egress_external" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-egress-external", namespace = "argocd" }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
      egress = [{
        to = [{
          ipBlock = {
            cidr = "0.0.0.0/0"
            except = [
              var.cluster_cidr,
              "10.96.0.0/12",
              "192.168.0.0/16"
            ]
          }
        }]
        ports = [
          { port = 443, protocol = "TCP" }, # git repos + OIDC
          { port = 22, protocol = "TCP" }   # git over SSH
        ]
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
# Webhook note: same IPIP/tunl0 reason as external-secrets above.
# ===========================================================================

resource "kubernetes_manifest" "netpol_metallb_allow_ingress_webhook" {
  depends_on = [helm_release.metallb]
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

# Controller and speaker coordinate IP assignment over the pod network. Note: the speaker's
# ARP advertisement traffic uses hostNetwork and is outside the scope of NetworkPolicies.
resource "kubernetes_manifest" "netpol_metallb_allow_internal" {
  depends_on = [helm_release.metallb]
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
  depends_on = [helm_release.metallb]
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
