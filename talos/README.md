# talos

Bootstraps and manages the Talos/Kubernetes cluster on VMs already provisioned by
[proxmox-terraform](https://git.thompson-manor.org/toast-dog/proxmox-terraform) — cluster PKI,
machine config, etcd bootstrap, node membership, and both Talos OS and Kubernetes version
upgrades. First unit in the chain; nothing needs to exist before it besides the VMs themselves.

## Files

```
machine_secrets.tf   Cluster PKI (etcd/Kubernetes CAs, bootstrap token, cluster ID/secret)
machine_config.tf    Rendered machine config per role + talos_machine (applies config to nodes)
cluster.tf           etcd bootstrap, kubeconfig fetch, local kubeconfig file
nodes.tf             Node IP locals, derived from vars
outputs.tf           kubernetes_client_configuration — structured output for future consumers
talosconfig.tf       Local talosconfig file, for talosctl convenience
providers.tf         talos provider (no provider-level auth — passed per-resource)
patches/             Machine config patches (VIP, install disk/image), plain YAML
```

## Usage

```bash
export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>
make plan   # from the repo root
make apply
```

Node topology (`talos_control_plane_ips`, `talos_worker_ips`) is manually maintained in
`terraform.tfvars`, not read from proxmox-terraform's state — see "Adding a node" below for why.

## Adding a node

1. **proxmox-terraform first**: copy an existing node's block in `proxmox.auto.tfvars`, give it a
   free `vmid` and an IP outside the DHCP pool, no `mac` field (Proxmox assigns one; the router
   module builds the DHCP reservation from it automatically). Apply — the VM boots into Talos
   maintenance mode.
2. **Then here**: add the new IP to `talos_control_plane_ips` or `talos_worker_ips`. For
   control-plane, append — don't prepend. `local.controlplane_ip` (element `[0]`) anchors
   `talos_cluster.bootstrap`'s and `talos_cluster_kubeconfig`'s target node; reordering the list
   silently redirects those. Leave the new IP out of `talos_joined_ips` — it hasn't joined yet.
3. `make plan`. For a new control-plane node, confirm `talos_cluster.bootstrap` shows
   `~ update in-place` for `control_plane_nodes`, not a replace — that would mean it's trying to
   re-bootstrap an already-running cluster.
4. `make apply`. Multiple new nodes can go in the same apply — `-parallelism=1`
   (`terragrunt.hcl`) serializes them, and joining is automatic once a node's config matches the
   existing cluster secrets/endpoint.
5. Once healthy, add the IP to `talos_joined_ips` in a follow-up apply to enable graceful drain
   for future upgrades.

## Removing a node

No manual `kubectl cordon`/`drain` needed — confirmed live, twice, by deliberately *not* running
either and watching what happened. `on_destroy`'s reset cordons the node itself (`talos.dev/cordoned:
true` annotation, a `NodeNotSchedulable` event) and kubelet gracefully stops whatever's running
there (`Killing` / `Stopping container`) before the wipe, with no `kubectl` involvement at all —
a live ReplicaSet-managed pod got replaced elsewhere within ~3 seconds of the node starting its
teardown, no visible gap in the Deployment's availability. Not confirmed: whether this respects
PodDisruptionBudgets or guarantees a replacement is ready *before* killing the original the way
an explicit `kubectl drain` does — for anything PDB-sensitive, draining manually first is still
the more conservative choice, just not a required one.

1. Remove the IP from `talos_control_plane_ips`/`talos_worker_ips` (and `talos_joined_ips`).
2. `make plan` — confirm the node shows `- destroy` (this is what actually triggers
   `on_destroy`'s reset+graceful-etcd-leave; a bare list removal that never plans a destroy does
   nothing to the live node).
3. `make apply`.
4. `kubectl delete node <name>` — the stale Node object never cleans itself up on its own,
   confirmed by direct testing, not assumed.
5. Remove the node's block from proxmox-terraform's `proxmox.auto.tfvars` and apply, to destroy
   the VM.

If a node is already dead/unreachable, step 2's graceful path can't work (nothing to talk to) —
fall back to `talosctl etcd remove-member` against a surviving node, then `terraform state rm`
the resource, then destroy the VM.

## Upgrading Talos and/or Kubernetes

**These are two separate applies, always** — confirmed against
[Sidero's own docs](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/lifecycle-management/upgrading-talos):
"An upgrade of the Talos Linux OS will not... apply an upgrade to the Kubernetes version by
default. Kubernetes upgrades should be managed separately." Bumping both in one apply can fail
outright — `talos_cluster.bootstrap`'s Kubernetes upgrade doesn't wait for every node to be on
the new Talos version, so it can try to run a newer Kubernetes release against a node still on
an older, incompatible Talos version.

### 1. Talos OS version

1. **Bump the ISO and the install image together** — `proxmox-terraform`'s
   `proxmox.auto.tfvars` Talos ISO URL and `terraform.tfvars`'s `talos_image` must move as a
   pair, same schematic ID, same version tag. This isn't just tidiness: a newer Talos release can
   introduce new machine-config document kinds (e.g. `UnattendedInstallConfig`,
   `DiscoveryServiceConfig`, both new in v1.14), and a node still booting from an *older* ISO's
   maintenance mode genuinely cannot parse a config that references a document kind it's never
   heard of — confirmed live (`"DiscoveryServiceConfig" "v1alpha1": not registered"`). This is a
   hard parse failure, not something patchable around; the ISO has to already be on-or-past the
   version being targeted.
2. Apply `proxmox-terraform` (updates the downloaded ISO for future/reset nodes).
3. Bump `talos_version` and `talos_image` in `talos/terraform.tfvars`. Leave
   `kubernetes_version` untouched.
4. `make plan`/`make apply`. Control-plane nodes upgrade first (dependency-ordered), then
   workers, each serially, each gracefully drained if already in `talos_joined_ips`.
5. Verify with `talosctl version -n <ip> -e <ip>` per node — not `kubectl get nodes`, which only
   shows kubelet/Kubernetes version and can't catch a Talos-level mismatch (this is exactly how a
   real bug here went unnoticed: a fresh node silently installed an unrelated prerelease build
   instead of the pinned version, and `kubectl` looked completely normal throughout).

### 2. Kubernetes version

Only after every node is confirmed on the target Talos version.

1. Bump `kubernetes_version` alone in `terraform.tfvars`.
2. `make plan` — should show only `talos_cluster.bootstrap` changing.
3. `make apply`. Watch progress with:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-apiserver -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}'
   kubectl get events -A --sort-by='.lastTimestamp' | tail -15
   ```
   This is health-gated and rolls one control-plane component at a time — a long "Still
   modifying..." is normal, not stuck.

## Gotchas / operational notes

- **VIP failover is not instant on an ungraceful failure.** A graceful shutdown reassigns the
  VIP almost immediately; a hard power-off waits out an etcd lease-expiry timeout first (up to
  ~a minute) specifically to avoid split-brain. Confirmed live: closer to 15s in practice, but
  don't expect sub-second.
- **etcd quorum**: a 3-node control plane tolerates exactly 1 node down. A 2nd simultaneous
  failure freezes the cluster (no new writes/scheduling; already-running pods keep running) until
  a node comes back — confirmed live, self-recovers automatically once a majority is reachable
  again. No special recovery needed unless a node is permanently gone (see "Removing a node"'s
  disaster-recovery fallback).
- **`talos_machine_secrets.talos_version` changing is not fully documented by the provider.**
  Tested once live (v1.13 → v1.14 contract, on an already-bootstrapped cluster): every cert/key
  in the resource shows as `known after apply` on plan, which looked alarming, but the cluster
  came through with no trust/connectivity issues. That's one data point, not a guarantee — watch
  it closely on future version bumps rather than assuming it's always safe.
- **`installer.image` (not top-level `image`, not `provisioning.image`) is the correct field**
  inside `UnattendedInstallConfig` for pinning a fresh install's version — confirmed against the
  [official field reference](https://docs.siderolabs.com/talos/v1.14/reference/configuration/runtime/unattendedinstallconfig)
  after two wrong guesses. Leaving it unset silently falls back to "current Talos version and
  current schematic," which is not necessarily the exact release you want.

## Outstanding

- **No `talos_machine_secrets` backup.** State is local-only (see repo root README) — losing
  this machine's disk would strand Terraform's ability to manage the cluster with no recovery
  path. The provider supports `terraform import talos_machine_secrets.cluster <path>` for
  recovery, but the exact importable-file schema needed to reconstruct one from a backup hasn't
  been verified yet.
- **Stale Node object cleanup is manual.** Could be automated (a `null_resource` with
  `local-exec` tied to a node's removal) but hasn't been — deliberate, not an oversight.
