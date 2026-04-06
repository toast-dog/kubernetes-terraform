# ---------------------------------------------------------------------------
# Shared — injected by root.hcl
# ---------------------------------------------------------------------------

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

# domain is passed by root.hcl but not used directly in this module —
# declared here to avoid "value for undeclared variable" warnings from Terragrunt
variable "domain" {
  type = string
}

variable "control_plane_ips" {
  type = list(string)
}

variable "cluster_cidr" {
  type = string
}

# ---------------------------------------------------------------------------
# MetalLB
# ---------------------------------------------------------------------------

variable "metallb_version" {
  type = string
}

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------

variable "cert_manager_version" {
  type = string
}

# ---------------------------------------------------------------------------
# Traefik
# ---------------------------------------------------------------------------

variable "traefik_version" {
  type = string
}

variable "traefik_load_balancer_ip" {
  description = "Fixed IP from the MetalLB pool to assign to the Traefik LoadBalancer service"
  type        = string
}

# ---------------------------------------------------------------------------
# Longhorn
# ---------------------------------------------------------------------------

variable "longhorn_version" {
  type = string
}

variable "longhorn_replica_count" {
  description = "Number of Longhorn volume replicas — should match the number of worker nodes"
  type        = number
  default     = 3
}
