# kubernetes-terraform

Terraform configuration for defining Kubernetes resources. Currently installs MetalLB for LoadBalancer IP allocation.

## What it does

1. Installs MetalLB via Helm
2. Configures an IP address pool for LoadBalancer services
3. Configures L2 advertisement for the IP pool

## Prerequisites

- Terraform installed locally
- A running Kubernetes cluster (provisioned by cluster-bootstrap)
- kubeconfig available locally (fetched automatically by cluster-bootstrap)

## Usage

On a fresh cluster the MetalLB CRDs don't exist yet, so a two-step apply is required:

```bash
terraform init

# Step 1: install Helm charts and their CRDs
make plan-helm
make apply

# Step 2: apply everything else (IPAddressPool, L2Advertisement)
make plan
make apply
```

On subsequent runs a single `make plan && make apply` is sufficient.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `metallb_version` | `0.15.3` | MetalLB Helm chart version |
| `metallb_ip_range` | — | IP range for LoadBalancer services (e.g. `192.168.30.160-192.168.30.170`) |
| `kubeconfig_path` | `~/.kube/config` | Path to kubeconfig |
