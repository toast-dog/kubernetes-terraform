variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for the Kubernetes cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "metallb_version" {
  description = "MetalLB Helm chart version"
  type        = string
  default     = "0.15.3" # renovate: datasource=helm registryUrl=https://metallb.github.io/metallb depName=metallb
}

variable "metallb_ip_range" {
  description = "IP range for MetalLB to assign to LoadBalancer services"
  type        = string
}
