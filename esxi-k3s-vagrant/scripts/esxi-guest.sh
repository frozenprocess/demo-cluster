#!/bin/bash

set -euo pipefail

NAME="${1:-small}"
MEM="${2:-1024}"
CPUS="${3:-1}"
ESXI_IP="${4:-192.168.122.10}"
PW="${5:?ESXi root password required}"
VLAN="${6:-150}"                       # 802.1Q tag for the workload VLAN
STATIC_IP="${7:-192.168.150.50/24}"    # no DHCP on the tagged VLAN -> static

DS="${DS:-datastore1}"
VSWITCH="${VSWITCH:-vSwitch0}"
UPLINK="${UPLINK:-vmnic1}"             # trunk NIC, uplink for a non-default vSwitch
PORTGROUP="${PORTGROUP:-vlan${VLAN}}"
GOVC_VERSION="${GOVC_VERSION:-v0.51.0}"
IMG_URL="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/generic_alpine-3.24.1-x86_64-bios-cloudinit-r0.qcow2"
CACHE="$HOME/esxi-guest-cache"

export GOVC_URL="https://root:${PW}@${ESXI_IP}/sdk"
export GOVC_INSECURE=1   # ponytail: self-signed ESXi cert on a lab host

# govc goes in the cache dir, not /usr/local/bin: this whole script runs
# unprivileged.
mkdir -p "$CACHE"
export PATH="$CACHE:$PATH"
if ! command -v govc >/dev/null; then
  echo "installing govc ${GOVC_VERSION} into $CACHE..."
  curl -fsSL "https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govc_Linux_x86_64.tar.gz" \
    | tar -xz -C "$CACHE" govc
  chmod +x "$CACHE/govc"
fi

# ESXi reboots into the installed system minutes after esxi-run.sh returns, so
# wait for the API before driving it (makes this safe right after install).
echo "waiting for ESXi API at ${ESXI_IP} (up to 10m)..."
for _ in $(seq 1 60); do
  govc about >/dev/null 2>&1 && break
  sleep 10
done
govc about >/dev/null 2>&1 || { echo "ESXi API not reachable at ${ESXI_IP}"; exit 1; }

if govc vm.info "$NAME" 2>/dev/null | grep -q "Name:"; then
  echo "guest '$NAME' already exists on ESXi"
  govc vm.power -on "$NAME" 2>/dev/null || true
  exit 0
fi

mkdir -p "$CACHE"
cd "$CACHE"

# Alpine virt cloud image -> streamOptimized VMDK (the format ESXi accepts).
[ -f alpine.qcow2 ] || curl -fsSL -o alpine.qcow2 "$IMG_URL"

rm -f disk.vmdk
qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized alpine.qcow2 disk.vmdk

# cloud init
cat > user-data <<UD
#cloud-config
password: alpine
chpasswd: { expire: false }
ssh_pwauth: true
write_files:
- path: /etc/network/interfaces
  content: |
    auto lo
    iface lo inet loopback

    auto eth0
    iface eth0 inet static
        address ${STATIC_IP}
runcmd:
- [ service, networking, restart ]
UD
echo "instance-id: ${NAME}-01" > meta-data
xorriso -as mkisofs -V CIDATA -J -R -o seed.iso user-data meta-data

# Upload the disk + seed to a per-VM datastore folder, then build the VM around
# them. import.vmdk converts the streamOptimized upload into a datastore disk.
echo "uploading disk + seed to [$DS] $NAME/ ..."
# The VM does not exist (guard above), so anything in its folder is debris from
# a partial run -- import.vmdk refuses to overwrite, so clear it first.
govc datastore.rm -ds "$DS" -f "$NAME" 2>/dev/null || true
govc datastore.mkdir -ds "$DS" -p "$NAME"
govc datastore.upload -ds "$DS" seed.iso "$NAME/seed.iso"
govc import.vmdk -ds "$DS" disk.vmdk "$NAME"

if [ "$VSWITCH" != vSwitch0 ] \
   && ! govc host.vswitch.info | grep -qE "^Name: +${VSWITCH}$"; then
  echo "creating $VSWITCH with uplink $UPLINK..."
  govc host.vswitch.add -nic "$UPLINK" "$VSWITCH"
fi

echo "ensuring port group '$PORTGROUP' (VLAN ${VLAN}) on ${VSWITCH}..."
govc host.portgroup.add -vswitch "$VSWITCH" -vlan "$VLAN" "$PORTGROUP" 2>/dev/null || true

echo "creating VM '$NAME' (${CPUS} vcpu / ${MEM}MB) on VLAN ${VLAN}..."
govc vm.create -on=false -m "$MEM" -c "$CPUS" -g otherLinux64Guest \
  -net "$PORTGROUP" -ds "$DS" "$NAME"
govc vm.disk.attach -vm "$NAME" -ds "$DS" -disk "$NAME/disk.vmdk"
govc device.cdrom.add -vm "$NAME" >/dev/null
govc device.cdrom.insert -vm "$NAME" -ds "$DS" "$NAME/seed.iso"
govc vm.power -on "$NAME"

echo "guest '$NAME' powered on (VLAN ${VLAN}, static ${STATIC_IP}). Login"
echo "alpine/alpine; it shares the k8s VMs' L2 domain (192.168.150.0/24)."
