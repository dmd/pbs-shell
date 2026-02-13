#!/usr/bin/env bash
set -euo pipefail

TEST_SNAPSHOT="${TEST_SNAPSHOT:-vm/102/2026-02-09T08:00:18Z}"
TEST_ARCHIVE="${TEST_ARCHIVE:-drive-scsi0.img.fidx}"
TEST_PARTITION="${TEST_PARTITION:-}"

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
out="$(proxmox-backup-client map "$TEST_SNAPSHOT" "$TEST_ARCHIVE" 2>&1)"
loop=$(echo "$out" | grep -Eo '/dev/loop[0-9]+' | head -n1)
[[ -n "$loop" ]] || {
  echo "Unable to map image target from output:" >&2
  echo "$out" >&2
  exit 1
}

while read -r dev majmin type; do
  [[ "$type" == "part" ]] || continue
  [[ -b "$dev" ]] || mknod "$dev" b "${majmin%%:*}" "${majmin##*:}" || true
done < <(lsblk -lnpo NAME,MAJ:MIN,TYPE "$loop")

target_part="$TEST_PARTITION"
if [[ -z "$target_part" ]]; then
  while read -r part; do
    fstype="$(blkid -o value -s TYPE "$part" 2>/dev/null || true)"
    case "$fstype" in
      ext2|ext3|ext4|xfs|btrfs)
        target_part="$part"
        break
        ;;
    esac
  done < <(lsblk -lnpo NAME,TYPE "$loop" | awk '$2=="part" {print $1}')
fi

[[ -n "$target_part" ]] || {
  echo "No mountable non-LVM partition found under $loop" >&2
  exit 1
}

mount -o ro "$target_part" /mnt/test
echo "EXT_OK $target_part"
find /mnt/test -mindepth 1 -maxdepth 1 -print | head -n 5
