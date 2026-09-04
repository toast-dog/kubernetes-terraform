# kubernetes-terraform

Terragrunt configuration for the homelab's Talos/Kubernetes cluster.

## Module Layout

```
talos/   Talos cluster bootstrap and lifecycle — machine secrets, node config,
         etcd bootstrap, node add/remove, Talos + Kubernetes version upgrades.
         See talos/README.md.
```

`talos/` is currently the only active module. The app-layer modules that used to live here
(`core-helm`, `core`, `argocd`, `apps/argocd`, `secrets` — MetalLB, cert-manager, Traefik,
Longhorn, External Secrets Operator, ArgoCD) were archived as part of a broader simplification
pass and haven't been rebuilt on top of Talos yet. RUNBOOK.md describes that pre-Talos design —
treat it as reference material for the rebuild, not a runnable process against the current repo.

## Usage

```bash
export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>
make plan
make apply
```

The token is required at plan time — every module needs `onepassword_vault_id` (injected via
`op run --environment`, see the Makefile), even before any module actually reads a secret from
the vault.

```bash
# Upgrade provider lock files after a version bump in root.hcl
make upgrade

# Wipe state for cluster-scoped modules only, before a fresh cluster rebuild
make wipe-state
```

**Tip:** use the 1Password CLI to avoid pasting the token manually:
```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(op read "op://<vault>/<item>/<field>")
make plan
make apply
```

## State

Local backend (`root.hcl`'s `remote_state` block) — each module's state lives under
`.terraform-state/<module>/terraform.tfstate` on disk, not in a remote backend. This is a known
gap, particularly for `talos/`: its state holds `talos_machine_secrets`, the only copy of the
cluster's PKI root of trust, with no backup elsewhere yet. Losing this machine's disk wouldn't
take the running cluster down, but would strand Terraform's ability to manage it. Worth revisiting
if this ever needs to be usable from both a local machine and Atlantis.

## Related Repositories

| Repo | Purpose |
|------|---------|
| [proxmox-terraform](https://git.thompson-manor.org/toast-dog/proxmox-terraform) | Provisions the VMs this cluster runs on |
| [kubernetes-apps](https://git.thompson-manor.org/toast-dog/kubernetes-apps) | ArgoCD app-of-apps: CloudNativePG, Authentik, Atlantis |
| [tf-authentik](https://git.thompson-manor.org/toast-dog/tf-authentik) | Authentik provider configuration (providers, outposts, applications, groups) |
