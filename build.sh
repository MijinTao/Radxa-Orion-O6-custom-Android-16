#!/bin/bash
# Builds Android 16 for the Radxa Orion O6 (CIX's Android 16 tree + the patches in ./patches) in Docker
# and puts the result in ./output.
#
#   ./build.sh --o6                    Orion O6, userdebug -> ./output/O6-Android16-userdebug/
#   ./build.sh --o6 --variant user     user build          -> ./output/O6-Android16-user/
#   ./build.sh --o6 --stock            CIX's tree without the patches -> ...-stock/
#   ./build.sh --o6 --latest --sync    newest CIX manifest instead of the pinned one (patches may not apply)
#   ./build.sh --o6 --wifi-country DE  another Wi-Fi country code (the patches set IT)
#   ./build.sh --o6 --cpus 16 --memory 48   limit the build container to 16 CPUs and 48 GB of RAM
#   ./build.sh --o6 --verbose-console  leave out patch 0014: full kernel log on the serial console
#
# Without --o6 / --o6n it builds the O6. --o6n stops with an explanation: CIX's tree has no O6N device.
# Other options: --jobs <n>, --output <dir>. The first run downloads ~90 GB and takes several hours.
set -euo pipefail

BOARDS=()
VARIANT="userdebug"
PATCHES="1"
MANIFEST="pinned"
SYNC="0"
JOBS=""
CPUS=""
MEMORY=""
WIFI_COUNTRY=""
SKIP_PATCHES=""
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$HERE/output"
IMAGE="${IMAGE:-radxa-o6-android16-builder}"
SOURCE_VOLUME="${SOURCE_VOLUME:-radxa-o6-android16-src}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --o6|--O6)      BOARDS+=("O6"); shift ;;
    --o6n|--O6N)    BOARDS+=("O6N"); shift ;;
    --stock)        PATCHES="0"; shift ;;
    --variant)      VARIANT="$2"; shift 2 ;;
    --latest)       MANIFEST="latest"; shift ;;
    --sync)         SYNC="1"; shift ;;
    --jobs)         JOBS="$2"; shift 2 ;;
    --cpus)         CPUS="$2"; shift 2 ;;
    --memory)       MEMORY="$2"; shift 2 ;;
    --wifi-country) WIFI_COUNTRY="$2"; shift 2 ;;
    --output)       OUTPUT_DIR="$2"; shift 2 ;;
    --verbose-console) SKIP_PATCHES="0014"; shift ;;
    -h|--help)      sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done
if [[ ${#BOARDS[@]} -eq 0 ]]; then BOARDS=("O6"); echo "No board given: building the Orion O6."; fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

docker build -t "$IMAGE" "$HERE"
docker volume create "$SOURCE_VOLUME" >/dev/null
for BOARD in "${BOARDS[@]}"; do
  echo; echo "=== Building Android 16 for the $BOARD ($VARIANT) ==="
  extra=(); limits=()
  # Without --jobs the build uses one job per allowed CPU (nproc in the container ignores --cpus).
  jobs="$JOBS"; [[ -z "$jobs" && -n "$CPUS" ]] && jobs="${CPUS%.*}"
  [[ -n "$jobs" ]] && extra+=(-e "JOBS=$jobs")
  [[ -n "$CPUS" ]] && limits+=(--cpus "$CPUS")
  [[ -n "$MEMORY" ]] && limits+=(--memory "${MEMORY}g" --memory-swap "${MEMORY}g")
  [[ ${#limits[@]} -gt 0 ]] && echo "Limits: ${limits[*]}  jobs: ${jobs:-all CPUs}"
  [[ -n "$WIFI_COUNTRY" ]] && extra+=(-e "WIFI_COUNTRY=$WIFI_COUNTRY")
  [[ -n "$SKIP_PATCHES" ]] && { extra+=(-e "SKIP_PATCHES=$SKIP_PATCHES"); echo "Leaving out patch(es) $SKIP_PATCHES"; }
  docker run --rm -t "${limits[@]}" \
    -v "$SOURCE_VOLUME:/work" \
    -v "$OUTPUT_DIR:/out" \
    -e BOARD="$BOARD" -e VARIANT="$VARIANT" -e PATCHES="$PATCHES" -e MANIFEST="$MANIFEST" -e SYNC="$SYNC" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    "${extra[@]}" \
    "$IMAGE"
done

echo "Done (${BOARDS[*]}). Output in $OUTPUT_DIR"
ls -l "$OUTPUT_DIR"
