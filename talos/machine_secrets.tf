# Cluster PKI — etcd/Kubernetes CAs, bootstrap token, cluster ID/secret. Generated once.
resource "talos_machine_secrets" "cluster" {
  talos_version = var.talos_version
}
