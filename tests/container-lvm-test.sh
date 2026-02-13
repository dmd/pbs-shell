#!/usr/bin/env bash
set -euo pipefail

set -a
source /app/auth.env
set +a

cleanup() {
  umount /mnt/test >/dev/null 2>&1 || true
  if [[ -n "${dm:-}" ]]; then
    dmsetup remove "$dm" >/dev/null 2>&1 || true
  fi
  if [[ -n "${loop:-}" ]]; then
    proxmox-backup-client unmap "$loop" >/dev/null 2>&1 || true
    losetup -d "$loop" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p /mnt/test
out=$(proxmox-backup-client map vm/102/2026-02-09T08:00:18Z drive-scsi0.img.fidx 2>&1)
loop=$(echo "$out" | grep -Eo '/dev/loop[0-9]+' | head -n1)

while read -r dev majmin type; do
  [[ "$type" == "part" ]] || continue
  [[ -b "$dev" ]] || mknod "$dev" b "${majmin%%:*}" "${majmin##*:}" || true
done < <(lsblk -lnpo NAME,MAJ:MIN,TYPE "$loop")

pv="${loop}p3"
cfg="devices { filter=[\"a|^${pv}$|\",\"r|.*|\"] }"
vg_name=$(lvm pvs --config "$cfg" --noheadings -o vg_name "$pv" | xargs)
vg_uuid=$(lvm pvs --config "$cfg" --noheadings -o vg_uuid "$pv" | xargs)
lv_name=ubuntu-lv

pe_start=$(lvm pvs --config "$cfg" --units s --nosuffix --noheadings -o pe_start "$pv" | awk '{gsub(/ /,""); sub(/s$/,""); print int($1)}')
pe_size=$(lvm vgs --config "$cfg" --units s --nosuffix --noheadings -o vg_extent_size "$vg_name" | awk '{gsub(/ /,""); sub(/s$/,""); print int($1)}')

table=$(lvm lvs --config "$cfg" --noheadings --separator '|' -o seg_start_pe,seg_size_pe,devices "${vg_name}/${lv_name}" | \
  awk -F'|' -v ps="$pe_size" -v pstart="$pe_start" '
    {
      gsub(/^ +| +$/, "", $1)
      gsub(/^ +| +$/, "", $2)
      gsub(/^ +| +$/, "", $3)
      pvdev=$3
      sub(/\(.*/, "", pvdev)
      pvpe=$3
      sub(/^.*\(/, "", pvpe)
      sub(/\).*/, "", pvpe)
      printf "%d %d linear %s %d\n", $1*ps, $2*ps, pvdev, pstart + pvpe*ps
    }
  ')

dm="pbs-${vg_uuid//-/}-ubuntu-lv-$$"
dmsetup create "$dm" --readonly --table "$table"
dmsetup mknodes
mount -o ro "/dev/mapper/$dm" /mnt/test

echo "LVM_OK"
ls /mnt/test | head -n 5
