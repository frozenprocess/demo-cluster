# ESXi + k3s + Calico Enterprise L2 — one host, Vagrant + libvirt

Standalone lab: a VMware **ESXi** hypervisor and an Ubuntu **k3s** node run as
KVM guests on one libvirt host, wired through an isolated bridge that plays the
part of a physical switch. An ESXi guest and a KubeVirt VM end up in the same
VLAN-150 broadcast domain, governed by Calico Enterprise's L2 (dot1q) feature.

```
   ┌──────────┐        vagrant mgmt NAT (DHCP, internet)         ┌──────────┐
   │   esxi   │ vmnic0 ── virbr0 .10        192.168.121.x ─ ens5 │ l2node   │
   │ 8.0U3 or │                                                 │ k3s +    │
   │ 9.1.0    │ vmnic1 ─── br-l2trunk (isolated) ────── ens6 ─── │ Calico + │
   └────┬─────┘  vSwitch1/vlan150       VLAN150 trunk            │ KubeVirt │
        │                                                        └────┬─────┘
   guest "small"                                              app-0 / app-1
   192.168.150.50   ◄── Calico L2 · VLAN150 · 192.168.150.0/24 ──►  .192/.193
```

Vagrant owns the node VM (box, second NIC, synced folder, provisioning). ESXi is
**not** a Vagrant box — it installs from an ISO with a remastered kickstart, UEFI
boot and two disks — so `scripts/esxi-run.sh` builds it with `virt-install` from
a `before :up` trigger. The isolated trunk network and the ESXi-side guest (built
over the ESXi API with govc) are triggers for the same reason.

Everything needed is in this directory; it does not depend on the rest of the
repo.

```
Vagrantfile              node VM + host-side triggers
scripts/libvirt-l2net.sh isolated trunk bridge (the "switch")
scripts/esxi-run.sh      ESXi VM: kickstart-over-HTTP unattended install
scripts/esxi-guest.sh    Alpine guest inside ESXi, on the tagged VLAN
scripts/l2-cluster-k3s.sh k3s + Calico Enterprise + Multus + KubeVirt + demo
manifests/               Calico L2 Network, pools, NADs, policy, KubeVirt VMs
manifests/vm-alpine.yaml small Alpine VM (alpine-0) that pings the ESXi guest
iso/                     drop the ESXi installer ISO here
enterprise_files/        docker.config, license.yaml, dev tigera-operator.yaml
```

## Prerequisites

- Linux host with `/dev/kvm`, `libvirtd`, the libvirt `default` network up
  (`virbr0`, 192.168.122.0/24), and `qemu-kvm virtinst ovmf xorriso curl`.
- `vagrant` + the `vagrant-libvirt` plugin
  (`vagrant plugin install vagrant-libvirt`), and `rsync` on host and guest.
- **Your user in the `libvirt` group** — that is the only privilege needed.
  Nothing here uses `sudo`: `virsh`/`virt-install` go through `qemu:///system`,
  the ISO is remastered with `xorriso -osirrox` instead of a loop mount, and
  `govc` installs into `~/esxi-guest-cache`.
- `iso/VMware-VMvisor-Installer-*.iso` (or set `ESXI_ISO`). Verified with
  **8.0U3** and **9.1.0**.
- `enterprise_files/docker.config` + `license.yaml`, plus a dev
  `tigera-operator.yaml` if your operator image needs the bundled Networks CRD.
- RAM: 8GB ESXi + 16GB node. On a 32GB host that is the whole budget — lower
  `NODE_MEM` and the LogStorage limits in `scripts/l2-cluster-k3s.sh` if
  Elasticsearch OOMs. Disk ~200GB.

## Run

```sh
export ESXI_PW='VMware1!'
export OPERATOR_IMAGE='docker.com/u/calico/operator:l2-phase-20260702_1811'
vagrant up
```

`OPERATOR_IMAGE` must be the **full** reference (`registry/repo:tag`); a bare tag
resolves to `docker.io/library/<tag>` and only shows up as an
`ImagePullBackOff` ten minutes in, so the Vagrantfile rejects it up front.

Order: trunk bridge → ESXi (unattended kickstart, ~15m to a usable API) → node
VM → k3s + Calico Enterprise + Multus + KubeVirt + the L2 demo resources (~20m;
Elasticsearch and the Manager are the slow parts) → Alpine guest inside ESXi.

Every step is idempotent and skips work that already exists, so re-running
`vagrant up` after a failure picks up where it stopped. Re-run just the
Kubernetes stack with `vagrant provision`.

### Knobs (all optional)

| var | default | |
|---|---|---|
| `RUN_ESXI` / `RUN_GUEST` / `RUN_L2` | `true` | skip a layer with `false` |
| `ESXI_PW` | *(empty)* | empty = interactive install over VNC instead of kickstart |
| `ESXI_ISO` | newest `iso/VMware-VMvisor-Installer-*.iso` | |
| `ESXI_IP` | `192.168.122.10` | static, pinned by the kickstart |
| `ESXI_MEM` / `ESXI_CPUS` / `ESXI_DISK` / `ESXI_DATASTORE_DISK` | 8192 / 4 / 40 / 40 | |
| `NODE_MEM` / `NODE_CPUS` / `NODE_DISK` | 16384 / 6 / 80 | |
| `OPERATOR_IMAGE` | — | required for `RUN_L2`; no released operator has the L2 CRD |
| `TRUNK_NET` | `l2trunk` | isolated libvirt network name |
| `WORKLOAD_VLAN` | `150` | must match `manifests/network.yaml` |
| `GUEST_IP` | `192.168.150.50/24` | ESXi guest, static (no DHCP on the VLAN) |

## Verify

```sh
vagrant ssh
kubectl get vmi -n virtual-machines -o wide         # app-0/app-1 on 192.168.150.x
ip -d link show ens6 | grep master                  # -> master calb-calico-l2
virtctl ssh ubuntu@vm/app-0 -n virtual-machines     # pw: ubuntu
#   inside app-0:  ping 192.168.150.50              # the ESXi guest, across the trunk
```

Verified end to end: `app-0` (192.168.150.192) reaches the ESXi guest
(192.168.150.50) with 0% loss once ICMP is allowed, over
VM -> `calb-calico-l2` -> `ens6` -> `br-l2trunk` -> ESXi `vmnic1` -> `vSwitch1`
port group `vlan150`.

`alpine-0` is the small Alpine VM whose whole job is that ping, and
`policy-3-allow-icmp.yaml` allows ICMP egress for it alone (`role: probe`), so it
succeeds while `app-0`/`app-1` stay blocked:

```sh
kubectl get vmi alpine-0 -n virtual-machines -o jsonpath='{.status.interfaces[*].ipAddress}'
virtctl console alpine-0 -n virtual-machines      # or ssh alpine@<pod IP>, pw: alpine
#   inside alpine-0:  ping 192.168.150.50         # 0% loss
```

Its VLAN NIC takes ~1-2 minutes to get a DHCP lease from KubeVirt's per-interface
DHCP server — `eth1` shows up with no address before that.

Selector warning: on this dev build the `projectcalico.org/network` label does
**not** carry the NAD name, so a policy selecting
`projectcalico.org/network == 'vm-vlan-150'` (as `policy-2-allow-http.yaml` does)
matches nothing. Use the `has(...) && != 'k8s-pod-network'` form that
`policy-1`/`policy-3` use.

The `demo-default-deny-vlan` GlobalNetworkPolicy blocks ICMP **by design** — ARP
is L2 and still resolves, so the MAC is learned while the ping fails. Delete that
policy (or apply `manifests/policy-2-allow-http.yaml`) to let traffic through:
that is the demo beat — the bridge carries the frames, Calico governs them.

UIs: ESXi at `https://192.168.122.10/ui` (root / `ESXI_PW`); Tigera Manager at
`https://<node eth0 IP>:9443` — the address and the login token path are printed
at the end of provisioning (token also at `~vagrant/ui-token.txt`).

## Teardown

```sh
vagrant destroy -f                                    # the node VM
virsh --connect qemu:///system destroy esxi
virsh --connect qemu:///system undefine esxi --nvram --remove-all-storage
virsh --connect qemu:///system net-destroy l2trunk
virsh --connect qemu:///system net-undefine l2trunk
```

`vagrant destroy` only removes the node — ESXi was built outside Vagrant, so it
is removed by hand as above.
