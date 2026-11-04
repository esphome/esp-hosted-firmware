#!/usr/bin/env bash
# Build the OpenThread RCP (ESP-IDF examples/openthread/ot_rcp) for the
# ESP32-H2 on the ESP Thread Border Router/Zigbee Gateway Board.
#
# Usage: build-ot-rcp.sh <target> <out-dir>
# Run with an exported ESP-IDF environment (IDF_PATH set).
#
# Produces in <out-dir>:
#   ot_rcp_<target>.bin    bootloader + partition table + app merged at 0x0,
#                          for flashing over the H2's own USB port
#   rcp_image_<target>.bin the same firmware in esp_rcp_update's container
#                          format, for the host to reflash the RCP over
#                          UART + RESET/BOOT
#   rcp_version_<target>   the RCP version string the RCP reports over Spinel
#   *.sha256               for each .bin
set -euo pipefail

TARGET="${1:?target}"
OUT="$(mkdir -p "${2:?out-dir}" && cd "$2" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"

# esp_rcp_update's image packer, pinned so the container format only changes
# when this commit is bumped.
ESP_THREAD_BR_REV=29a2345e3f0c61bba9307f3daea5ed0c94388ed3
PACKER_URL="https://raw.githubusercontent.com/espressif/esp-thread-br/${ESP_THREAD_BR_REV}/components/esp_rcp_update/create_ota_image.py"

: "${IDF_PATH:?export ESP-IDF first}"
WORK="${WORK_DIR:-$PWD/ot_rcp}"
rm -rf "$WORK"
cp -r "$IDF_PATH/examples/openthread/ot_rcp" "$WORK"
cp "$HERE/sdkconfig.defaults.thread_br" "$WORK/"

cd "$WORK"
idf.py -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.thread_br" set-target "$TARGET"
idf.py build

grep -q '^CONFIG_OPENTHREAD_UART_RX_PIN=23$' sdkconfig
grep -q '^CONFIG_OPENTHREAD_UART_TX_PIN=24$' sdkconfig

(cd build && esptool.py --chip "$TARGET" merge_bin -o "$OUT/ot_rcp_${TARGET}.bin" @flash_args)

curl -sSfL "$PACKER_URL" -o build/create_ota_image.py
python3 build/create_ota_image.py --rcp-build-dir build --target-file "$OUT/rcp_image_${TARGET}.bin"
cp build/rcp_version "$OUT/rcp_version_${TARGET}"

cd "$OUT"
for f in "ot_rcp_${TARGET}.bin" "rcp_image_${TARGET}.bin"; do
  sha256sum "$f" > "$f.sha256"
done
echo "RCP version: $(cat "rcp_version_${TARGET}")"
