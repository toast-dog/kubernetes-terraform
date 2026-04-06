# Pod Security Standards (PSS) labels for namespaces managed by this module.
# Helm releases (which create these namespaces) are in core-helm/ and are guaranteed
# to have run before this module. No depends_on needed.

resource "kubernetes_labels" "namespace_cert_manager" {
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

resource "kubernetes_labels" "namespace_traefik" {
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

# privileged — Longhorn engine and instance-manager DaemonSets require privileged containers.
# network-policy=managed intentionally omitted — see network-policies.tf.
resource "kubernetes_labels" "namespace_longhorn" {
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
