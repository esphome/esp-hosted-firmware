#!/usr/bin/env bash
#
# apply-overlay.sh — inject the ESP-NOW-over-CustomRpc slave overlay into a
# freshly scaffolded esp_hosted co-processor project (the 2.x `slave` example or
# a 3.x `cp` project), so the prebuilt co-processor firmware also carries
# ESP-NOW (which upstream esp-hosted does not yet proxy —
# espressif/esp-hosted-mcu#19).
#
# On the 2.x layout it performs only safe *appends* against the scaffolded project:
#   1. copies slave-overlay/{esp_now_hosted_slave.c,.h,esp_now_hosted_rpc.h}
#      into slave/main/;
#   2. registers esp_now_hosted_slave.c inside the existing
#      CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER block in main/CMakeLists.txt;
#   3. appends the two CustomRpc Kconfig options to sdkconfig.defaults.
#
# The overlay self-registers via a __constructor__ in esp_now_hosted_slave.c, so
# NO edit to the stock esp_hosted_coprocessor.c is required.
#
# Idempotent: running it twice is a no-op after the first application.
#
# Usage:  apply-overlay.sh [SLAVE_DIR]      (SLAVE_DIR defaults to ./slave)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/slave-overlay"
SLAVE_DIR="${1:-slave}"
MAIN_DIR="$SLAVE_DIR/main"
CMAKE="$MAIN_DIR/CMakeLists.txt"
DEFAULTS="$SLAVE_DIR/sdkconfig.defaults"

MARKER="esp-now-hosted overlay (added by apply-overlay.sh)"

log() { echo "apply-overlay: $*"; }
die() { echo "apply-overlay: ERROR: $*" >&2; exit 1; }

[ -d "$OVERLAY_DIR" ]  || die "overlay dir not found: $OVERLAY_DIR"
[ -d "$SLAVE_DIR" ]    || die "project dir not found: $SLAVE_DIR (run create-project-from-example first)"

# NOTE: slave-overlay/esp_now_hosted_rpc.h is the on-the-wire contract and must
# stay byte-identical to the copy the ESPHome host shim (esp32_hosted component)
# uses. If you revise the protocol, edit BOTH copies together.

# ── esp_hosted 3.x co-processor layout ───────────────────────────────────────
# 3.x scaffolds a plain IDF project (main/main.c + a three-line
# idf_component_register) on top of the esp_hosted component, and the CustomRpc
# channel is the eh_cp_feat_peer_data feature. The overlay sources compile
# against either API (see esp_now_hosted_slave.c), so here we only need to add
# the source, the component requirements, the force-link and the feature
# Kconfig. main/CMakeLists.txt is rewritten wholesale: it is tiny, and its
# stock content is known.
if [ -f "$CMAKE" ] && [ -f "$DEFAULTS" ] && grep -q "^CONFIG_ESP_HOSTED_CP=y" "$DEFAULTS"; then
  # Only ever replace the known stock file (or our own rewrite of it), so an
  # upstream change to main/CMakeLists.txt fails the build instead of being
  # silently dropped.
  STOCK_CMAKE='idf_component_register(SRCS"main.c"INCLUDE_DIRS"."REQUIRESnvs_flash)'
  if ! grep -qF "$MARKER" "$CMAKE" && [ "$(tr -d '[:space:]' < "$CMAKE")" != "$STOCK_CMAKE" ]; then
    die "$CMAKE is not the stock esp_hosted 3.x co-processor CMakeLists; update apply-overlay.sh"
  fi

  cp "$OVERLAY_DIR/esp_now_hosted_slave.c" "$MAIN_DIR/"
  cp "$OVERLAY_DIR/esp_now_hosted_slave.h" "$MAIN_DIR/"
  cp "$OVERLAY_DIR/esp_now_hosted_rpc.h"   "$MAIN_DIR/"
  log "copied overlay sources into $MAIN_DIR/ (esp_hosted 3.x layout)"

  cat > "$CMAKE" <<CMAKE_EOF
idf_component_register(
    SRCS          "main.c" "esp_now_hosted_slave.c"
    INCLUDE_DIRS  "."
    REQUIRES      nvs_flash esp_hosted
    PRIV_REQUIRES esp_wifi
)

# --- $MARKER ---
# Pull the self-registering ESP-NOW overlay object into the link (nothing
# references its symbols, so it would otherwise be garbage-collected).
target_link_libraries(\${COMPONENT_LIB} INTERFACE "-u esp_now_hosted_slave_init")
CMAKE_EOF
  log "rewrote $CMAKE with the overlay source, requirements and force-link"

  if grep -qF "$MARKER" "$DEFAULTS"; then
    log "sdkconfig.defaults already carries the overlay options (idempotent no-op)"
  else
    {
      echo ""
      echo "# --- $MARKER ---"
      echo "# esp-hosted CustomRpc (\"peer data transfer\") feature — carries ESP-NOW."
      echo "CONFIG_ESP_HOSTED_CP_FEAT_PEER_DATA=y"
    } >> "$DEFAULTS"
    log "appended overlay options to $DEFAULTS"
  fi

  log "ESP-NOW overlay applied."
  exit 0
fi

# ── Layout / version gate ────────────────────────────────────────────────────
# The overlay targets the esp_hosted 2.x "slave" example: a main/ component with
# the CustomRpc "peer data transfer" channel (esp_hosted >= 2.8.1). Skip — never
# fail — when the scaffolded project isn't that layout, so esp_hosted < 2.8.1
# (no CustomRpc) builds unmodified.
if [ ! -f "$CMAKE" ] \
   || ! grep -q "CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER" "$CMAKE" \
   || [ ! -f "$MAIN_DIR/esp_hosted_peer_data.h" ]; then
  log "project $SLAVE_DIR is not the esp_hosted 2.x slave layout with CustomRpc;"
  log "skipping ESP-NOW overlay — building the co-processor firmware unmodified."
  exit 0
fi

# ── 1. Copy overlay sources into main/ ──────────────────────────────────────
cp "$OVERLAY_DIR/esp_now_hosted_slave.c" "$MAIN_DIR/"
cp "$OVERLAY_DIR/esp_now_hosted_slave.h" "$MAIN_DIR/"
cp "$OVERLAY_DIR/esp_now_hosted_rpc.h"   "$MAIN_DIR/"
log "copied overlay sources into $MAIN_DIR/"

# ── 2. Register the source in main/CMakeLists.txt ───────────────────────────
if grep -q "esp_now_hosted_slave.c" "$CMAKE"; then
  log "CMakeLists already registers esp_now_hosted_slave.c (idempotent no-op)"
else
  # Insert immediately after the first CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER
  # if() line, so our source compiles under the same gate as the stock example.
  awk '
    !done && /if\(CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER\)/ {
      print
      print "\tlist(APPEND COMPONENT_SRCS esp_now_hosted_slave.c)"
      done = 1
      next
    }
    { print }
    END { if (!done) { print "AWK_NO_MATCH" > "/dev/stderr" } }
  ' "$CMAKE" > "$CMAKE.tmp" 2> "$CMAKE.awkerr"
  if grep -q AWK_NO_MATCH "$CMAKE.awkerr"; then
    rm -f "$CMAKE.tmp" "$CMAKE.awkerr"
    die "could not find the CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER if() block in $CMAKE"
  fi
  rm -f "$CMAKE.awkerr"
  mv "$CMAKE.tmp" "$CMAKE"
  log "registered esp_now_hosted_slave.c in $CMAKE"
fi

# ── 2b. Force the overlay object into the link ──────────────────────────────
# The overlay self-registers from a constructor and nothing references its
# symbols, so main's archive member would be dropped by the linker (exactly
# what happens to the stock example_peer_data_transfer.c). `-u <symbol>` marks
# esp_now_hosted_slave_init as undefined, pulling the object — and with it the
# constructor's .init_array entry — into the final image.
if grep -q "u esp_now_hosted_slave_init" "$CMAKE"; then
  log "CMakeLists already force-links the overlay (idempotent no-op)"
else
  {
    echo ""
    echo "# --- $MARKER ---"
    echo "# Pull the self-registering ESP-NOW overlay object into the link (nothing"
    echo "# references its symbols, so it would otherwise be garbage-collected)."
    echo 'target_link_libraries(${COMPONENT_LIB} INTERFACE "-u esp_now_hosted_slave_init")'
  } >> "$CMAKE"
  log "added force-link for the overlay to $CMAKE"
fi

# ── 3. sdkconfig.defaults ────────────────────────────────────────────────────
if [ -f "$DEFAULTS" ] && grep -qF "$MARKER" "$DEFAULTS"; then
  log "sdkconfig.defaults already carries the overlay options (idempotent no-op)"
else
  {
    echo ""
    echo "# --- $MARKER ---"
    echo "# esp-hosted CustomRpc (\"peer data transfer\") channel — carries ESP-NOW."
    echo "CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER=y"
    echo "# Slave registers 1 handler (the ESP-NOW REQ); keep >= the host component's"
    echo "# _MAX_CUSTOM_MSG_HANDLERS (8) so both ends agree."
    echo "CONFIG_ESP_HOSTED_MAX_CUSTOM_MSG_HANDLERS=8"
  } >> "$DEFAULTS"
  log "appended overlay options to $DEFAULTS"
fi

log "ESP-NOW overlay applied."
