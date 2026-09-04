talos_cluster_name = "lab"
talos_vip          = "192.168.30.150"
talos_version      = "v1.14"
kubernetes_version = "v1.37.0" # always bump kubernetes version seperate of talos version (usually after)

# Keep in sync with proxmox-terraform's Talos ISO (same schematic ID + version).
talos_image = "factory.talos.dev/installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.14.0"

talos_control_plane_ips = ["192.168.30.151", "192.168.30.152", "192.168.30.153"]
talos_worker_ips        = ["192.168.30.161", "192.168.30.162", "192.168.30.163"]

talos_joined_ips = ["192.168.30.151", "192.168.30.152", "192.168.30.153", "192.168.30.161", "192.168.30.162", "192.168.30.163"]
