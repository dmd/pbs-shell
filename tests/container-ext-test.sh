#!/usr/bin/env bash
set -euo pipefail

set -a
source /app/auth.env
set +a

cleanup() {
  umount /mnt/test >/dev/null 2>&1 || true
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

mount -o ro "${loop}p2" /mnt/test
echo "EXT_OK"
ls /mnt/test | head -n 5
