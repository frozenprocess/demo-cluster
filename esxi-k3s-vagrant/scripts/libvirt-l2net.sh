#!/bin/bash

set -euo pipefail

NET="${1:-l2trunk}"
V="virsh --connect qemu:///system"

command -v virt-install >/dev/null || { echo "ERROR: virtinst not installed"; exit 1; }
[ -e /dev/kvm ] || { echo "ERROR: /dev/kvm missing"; exit 1; }
$V net-list >/dev/null 2>&1 || {
  echo "ERROR: cannot reach qemu:///system -- add yourself to the 'libvirt' group"; exit 1; }

if $V net-info "$NET" >/dev/null 2>&1; then
  $V net-start "$NET" 2>/dev/null || true
  echo "network '$NET' already defined"
  exit 0
fi

$V net-define /dev/stdin <<EOF
<network>
  <name>$NET</name>
  <bridge name='br-$NET' stp='off' delay='0'/>
</network>
EOF
$V net-start "$NET"
$V net-autostart "$NET"
echo "isolated trunk network '$NET' up (bridge br-$NET)"
