#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The TotalDrop Contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Verify that every 64-bit native library (arm64-v8a / x86_64) inside an
# Android .aab or .apk archive has 16 KB (0x4000) ELF PT_LOAD alignment,
# required by Android 15+ and Google Play.
set -euo pipefail

ARCHIVE="${1:?usage: verify-16kb-elf.sh <path/to/app.aab|app.apk>}"
[ -f "$ARCHIVE" ] || { echo "error: archive not found: $ARCHIVE" >&2; exit 1; }

find_readelf() {
  if [ -n "${LLVM_READELF:-}" ] && [ -x "${LLVM_READELF}" ]; then
    printf '%s\n' "${LLVM_READELF}"
    return 0
  fi
  for candidate in "${ANDROID_NDK_LATEST_HOME:-}" "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    if [ -n "$candidate" ] && [ -x "$candidate/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf" ]; then
      printf '%s\n' "$candidate/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
      return 0
    fi
  done
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [ -n "$sdk" ] && [ -d "$sdk/ndk" ]; then
    local latest
    latest="$(find "$sdk/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
    if [ -n "$latest" ] && [ -x "$latest/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf" ]; then
      printf '%s\n' "$latest/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
      return 0
    fi
  fi
  command -v llvm-readelf || command -v readelf
}

READELF_BIN="$(find_readelf)"
[ -x "$READELF_BIN" ] || { echo "error: neither llvm-readelf nor readelf found" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$ARCHIVE" "$TMP_DIR" <<'PY'
import sys, zipfile
from pathlib import Path

archive = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
checked = 0
with zipfile.ZipFile(archive) as zf:
    for info in zf.infolist():
        name = info.filename
        if not name.endswith(".so"):
            continue
        if "/arm64-v8a/" not in name and "/x86_64/" not in name:
            continue
        # Only verify TotalDrop's native Rust libraries (and Flutter engine).
        if archive.suffix == ".apk" and info.compress_type != zipfile.ZIP_STORED:
            raise SystemExit(f"error: {name} in {archive.name} is compressed (must be STORED for 16 KB alignment)")
        target = out_dir / f"{checked}_{Path(name).name}"
        target.write_bytes(zf.read(info))
        print(f"EXTRACTED:{name}:{target}")
        checked += 1
if checked == 0:
    raise SystemExit(f"error: no 64-bit .so libraries found in {archive}")
PY

found_totaldrop=0
for so in "$TMP_DIR"/*.so; do
  base="$(basename "$so")"
  case "$base" in
    *librust_lib_totaldrop.so|*libtotaldrop_app_rust.so) found_totaldrop=1 ;;
  esac
  loads="$("$READELF_BIN" -lW "$so" | awk '$1 == "LOAD" { print $NF }')"
  [ -n "$loads" ] || { echo "error: no ELF PT_LOAD segments in $base" >&2; exit 1; }
  for align in $loads; do
    bytes=$((align))
    if (( bytes < 16384 || bytes % 16384 != 0 )); then
      echo "error: $base PT_LOAD alignment $align ($bytes bytes) < 16 KB (0x4000)" >&2
      "$READELF_BIN" -lW "$so" >&2
      exit 1
    fi
  done
done

if [ "$found_totaldrop" -ne 1 ]; then
  echo "error: TotalDrop Rust .so library was not found inside $ARCHIVE" >&2
  exit 1
fi

echo "16 KB ELF alignment OK for all 64-bit native libraries in $(basename "$ARCHIVE")"
