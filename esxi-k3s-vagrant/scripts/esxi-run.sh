#!/bin/bash

set -euo pipefail

NAME="${1:-esxi}"
MEM="${2:-8192}"
CPUS="${3:-4}"
DISK="${4:-40}"
ISO="${5:?iso path required}"
PW="${6:-}"
ESXI_IP="${7:-}"
DSSIZE="${8:-40}"
TRUNK_NET="${9:-}"

V="virsh --connect qemu:///system"

if $V dominfo "$NAME" >/dev/null 2>&1; then
  echo "VM '$NAME' already defined"
  $V domstate "$NAME"
  exit 0
fi

CDROM="$ISO"

if [ -n "$PW" ]; then
  # --- Serve the kickstart over HTTP on the libvirt bridge ---
  BRIDGE_IP=$(ip -4 addr show virbr0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
  : "${BRIDGE_IP:=192.168.122.1}"
  KSPORT=8321
  KSDIR="/tmp/esxi-ks"
  mkdir -p "$KSDIR"
  if [ -n "$ESXI_IP" ]; then
    NET="network --bootproto=static --device=vmnic0 --ip=$ESXI_IP --netmask=255.255.255.0 --gateway=$BRIDGE_IP --nameserver=$BRIDGE_IP"
  else
    NET="network --bootproto=dhcp --device=vmnic0"
  fi

  tee "$KSDIR/ks.cfg" >/dev/null <<KS
vmaccepteula
install --firstdisk --overwritevmfs
rootpw $PW
$NET
reboot
KS
  tee -a "$KSDIR/ks.cfg" >/dev/null <<'KSFB'
%firstboot --interpreter=busybox
vim-cmd hostsvc/enable_ssh
vim-cmd hostsvc/start_ssh
esxcli system settings advanced set -o /UserVars/SuppressShellWarning -i 1
# Format the first disk that has no partition table (the dedicated datastore
# disk; the install disk already has partitions) as VMFS-6 "datastore1".
for DEV in $(esxcli storage core device list | grep -E '^(t10|naa|mpx|eui)\.'); do
  DISK="/vmfs/devices/disks/$DEV"
  [ -e "$DISK" ] || continue
  # Empty disk = no partition table; getptbl's first line is "unknown"
  # (a partitioned disk reports "gpt"/"msdos"). The install disk is skipped.
  [ "$(partedUtil getptbl "$DISK" 2>/dev/null | head -1)" = unknown ] || continue
  partedUtil mklabel "$DISK" gpt
  END=$(partedUtil getUsableSectors "$DISK" | awk '{print $2}')
  partedUtil setptbl "$DISK" gpt "1 2048 $END AA31E02A400F11DB9590000C2911D1B8 0"
  vmkfstools -C vmfs6 -S datastore1 "${DISK}:1"
  break
done
KSFB

  pkill -f "http.server $KSPORT" 2>/dev/null || true

  while (exec 3<>/dev/tcp/"$BRIDGE_IP"/"$KSPORT") 2>/dev/null; do KSPORT=$((KSPORT + 1)); done
  setsid bash -c "nohup python3 -m http.server $KSPORT --bind $BRIDGE_IP --directory $KSDIR >$KSDIR/ks-http.log 2>&1" &
  sleep 1
  curl -fsS "http://$BRIDGE_IP:$KSPORT/ks.cfg" | diff -q - "$KSDIR/ks.cfg" >/dev/null || {
    echo "ERROR: kickstart not served on $BRIDGE_IP:$KSPORT -- see $KSDIR/ks-http.log"; exit 1; }

  WORK=$(mktemp -d)

  xorriso -osirrox on -indev "$ISO" -extract / "$WORK" >/dev/null 2>&1
  chmod -R u+w "$WORK"

  find "$WORK" -mindepth 1 -depth -name '*[A-Z]*' -execdir bash -c 'mv -- "$1" "${1,,}"' _ {} \;
  [ -f "$WORK/boot.cfg" ] || { echo "ERROR: $ISO does not look like an ESXi installer (no boot.cfg)"; exit 1; }

  for cfg in "$WORK/boot.cfg" "$WORK/efi/boot/boot.cfg"; do
    sed -i "s#^kernelopt=.*#kernelopt=runweasel ks=http://$BRIDGE_IP:$KSPORT/ks.cfg#" "$cfg"
  done

  CDROM="$KSDIR/${NAME}-ks.iso"

  rm -f "$CDROM"
  xorriso -as mkisofs -relaxed-filenames -J -R -o "$CDROM" \
    -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e efiboot.img -no-emul-boot \
    "$WORK"
  rm -rf "$WORK"
fi


virt-install \
  --connect qemu:///system \
  --virt-type kvm \
  --name "$NAME" \
  --memory "$MEM" \
  --vcpus "$CPUS" \
  --cpu host-passthrough \
  --boot uefi,hd,cdrom \
  --disk size="$DISK",bus=sata,format=qcow2 \
  --disk size="$DSSIZE",bus=sata,format=qcow2 \
  --disk path="$CDROM",device=cdrom,bus=sata \
  --network network=default,model=e1000e \
  ${TRUNK_NET:+--network network=$TRUNK_NET,model=e1000e} \
  --graphics vnc,listen=127.0.0.1 \
  --os-variant generic \
  --import \
  --noautoconsole

echo "ESXi VM '$NAME' created. VNC console:"
$V vncdisplay "$NAME"
