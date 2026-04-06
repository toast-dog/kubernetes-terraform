# NetworkPolicies for the vault and external-secrets namespaces.
# Global policies (DNS egress, default deny) are in core/network-policies.tf.
#
# See core/network-policies.tf for a full explanation of the webhook IPIP/tunl0 behavior.

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
  depends_on = [helm_release.vault, helm_release.external_secrets]
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
# address (within pod CIDR), not the node IP.
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

# ESO reads secrets from Vault to sync into Kubernetes Secrets.
resource "kubernetes_manifest" "netpol_external_secrets_allow_egress_vault" {
  depends_on = [helm_release.vault, helm_release.external_secrets]
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

# ESO writes synced secrets to the API server and watches ExternalSecret/SecretStore
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
