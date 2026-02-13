#!/usr/bin/env bash
set -euo pipefail

TEST_SNAPSHOT="${TEST_SNAPSHOT:-vm/102/2026-02-09T08:00:18Z}"
TEST_ARCHIVE="${TEST_ARCHIVE:-drive-scsi0.img.fidx}"
TEST_PV_PARTITION="${TEST_PV_PARTITION:-}"
TEST_LV_NAME="${TEST_LV_NAME:-}"

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

pv="$TEST_PV_PARTITION"
if [[ -z "$pv" ]]; then
  while read -r part; do
    fstype="$(blkid -o value -s TYPE "$part" 2>/dev/null || true)"
    if [[ "$fstype" == "LVM2_member" ]]; then
      pv="$part"
      break
    fi
  done < <(lsblk -lnpo NAME,TYPE "$loop" | awk '$2=="part" {print $1}')
fi
[[ -n "$pv" ]] || {
  echo "No LVM physical volume partition found under $loop" >&2
  exit 1
}

cfg="devices { filter=[\"a|^${pv}$|\",\"r|.*|\"] }"
vg_name=$(lvm pvs --config "$cfg" --noheadings -o vg_name "$pv" | xargs)
vg_uuid=$(lvm pvs --config "$cfg" --noheadings -o vg_uuid "$pv" | xargs)
[[ -n "$vg_name" && -n "$vg_uuid" ]] || {
  echo "Unable to resolve VG metadata from $pv" >&2
  exit 1
}

lv_candidates=()
if [[ -n "$TEST_LV_NAME" ]]; then
  lv_candidates+=("$TEST_LV_NAME")
else
  while read -r lv_name; do
    lv_name="$(echo "$lv_name" | xargs)"
    [[ -n "$lv_name" ]] && lv_candidates+=("$lv_name")
  done < <(lvm lvs --config "$cfg" --noheadings -o lv_name "$vg_name")
fi
[[ "${#lv_candidates[@]}" -gt 0 ]] || {
  echo "No LV candidates found in VG $vg_name" >&2
  exit 1
}

pe_start=$(lvm pvs --config "$cfg" --units s --nosuffix --noheadings -o pe_start "$pv" | awk '{gsub(/ /,""); sub(/s$/,""); print int($1)}')
pe_size=$(lvm vgs --config "$cfg" --units s --nosuffix --noheadings -o vg_extent_size "$vg_name" | awk '{gsub(/ /,""); sub(/s$/,""); print int($1)}')

mounted_lv=""
for lv_name in "${lv_candidates[@]}"; do
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
        if (pvdev == "" || pvpe == "") next
        printf "%d %d linear %s %d\n", $1*ps, $2*ps, pvdev, pstart + pvpe*ps
      }
    ')
  [[ -n "$table" ]] || continue

  dm="pbs-${vg_uuid//-/}-${lv_name//[^a-zA-Z0-9._-]/_}-$$"
  dmsetup remove "$dm" >/dev/null 2>&1 || true
  if ! dmsetup create "$dm" --readonly --table "$table" >/dev/null 2>&1; then
    dm=""
    continue
  fi
  dmsetup mknodes

  if mount -o ro "/dev/mapper/$dm" /mnt/test; then
    mounted_lv="$lv_name"
    break
  fi

  dmsetup remove "$dm" >/dev/null 2>&1 || true
  dm=""
done

[[ -n "$mounted_lv" ]] || {
  echo "Unable to mount any LV from VG $vg_name" >&2
  exit 1
}

echo "LVM_OK ${vg_name}/${mounted_lv}"
find /mnt/test -mindepth 1 -maxdepth 1 -print | head -n 5
