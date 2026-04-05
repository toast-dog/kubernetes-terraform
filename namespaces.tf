# Pod Security Standards (PSS) labels for all managed namespaces.
#
# Three enforcement levels:
#   privileged — no restrictions (required for workloads that need host access or privileged containers)
#   baseline   — blocks known privilege escalations; allows some capabilities and host ports
#   restricted — heavily restricted; requires non-root, drops all capabilities, no privilege escalation
#
# We set both `enforce` (rejects non-compliant pods) and `warn` (surfaces violations in kubectl output).
# See: https://kubernetes.io/docs/concepts/security/pod-security-standards/

# baseline — vault server pods only set allowPrivilegeEscalation: false; missing capabilities.drop: ALL
# and seccompProfile, both required for restricted. The Helm chart doesn't expose these as values.
resource "kubernetes_labels" "namespace_vault" {
  depends_on  = [helm_release.vault]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "vault"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "baseline"
    "pod-security.kubernetes.io/warn"    = "baseline"
    "network-policy"                     = "managed"
  }
}

# restricted — cert-manager chart sets proper security contexts on all containers
resource "kubernetes_labels" "namespace_cert_manager" {
  depends_on  = [helm_release.cert_manager]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "cert-manager"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
    "network-policy"                     = "managed"
  }
}

# restricted — ESO chart sets proper security contexts on all containers
resource "kubernetes_labels" "namespace_external_secrets" {
  depends_on  = [helm_release.external_secrets]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "external-secrets"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
    "network-policy"                     = "managed"
  }
}

# restricted — ArgoCD chart sets proper security contexts on all containers
resource "kubernetes_labels" "namespace_argocd" {
  depends_on  = [helm_release.argocd]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "argocd"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
    "network-policy"                     = "managed"
  }
}

# restricted — verified: pod runs as uid 65532 (non-root), seccompProfile: RuntimeDefault,
# allowPrivilegeEscalation: false, capabilities.drop: ALL, readOnlyRootFilesystem
resource "kubernetes_labels" "namespace_traefik" {
  depends_on  = [helm_release.traefik]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "traefik"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
    "network-policy"                     = "managed"
  }
}

# privileged — MetalLB speaker DaemonSet requires hostNetwork: true for L2 ARP advertisement
resource "kubernetes_labels" "namespace_metallb" {
  depends_on  = [helm_release.metallb]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "metallb-system"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "privileged"
    "pod-security.kubernetes.io/warn"    = "privileged"
    "network-policy"                     = "managed"
  }
}

# privileged — Longhorn engine and instance-manager DaemonSets require privileged containers
# for block device management; this is an upstream requirement, not configurable.
# network-policy=managed is intentionally omitted — Longhorn's attachdetach-controller
# originates from the control plane host network (outside pod network) and cannot be
# governed by NetworkPolicies. Restricting Longhorn causes volume attach failures on startup.
resource "kubernetes_labels" "namespace_longhorn" {
  depends_on  = [helm_release.longhorn]
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "longhorn-system"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "privileged"
    "pod-security.kubernetes.io/warn"    = "privileged"
  }
}
