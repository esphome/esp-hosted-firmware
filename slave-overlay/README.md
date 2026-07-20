# ESP-NOW slave overlay

Co-processor-side firmware overlay that adds **ESP-NOW to the ESP-Hosted
host↔co-processor link**. Upstream ESP-Hosted proxies `esp_wifi.h` but **not**
`esp_now.h` (tracking issue
[esp-hosted-mcu#19](https://github.com/espressif/esp-hosted-mcu/issues/19),
open). This overlay bridges the native `esp_now_*` API over ESP-Hosted's
**CustomRpc** ("peer data transfer") channel, so a radio-less host (e.g. an
ESP32-P4) can use ESP-NOW through the co-processor's radio. ESP-NOW itself is
fully native on the co-processor; the overlay only forwards it over the link.

Validated on real hardware (ESP32-P4 + ESP32-C6, ESP-Hosted 2.12.9) on
2026-07-20: bidirectional ESP-NOW with a native peer, plus Wi-Fi STA and ESP-NOW
running simultaneously — using ESPHome's `espnow` component unmodified.

## Files

| File | Role |
|:-------------------------|:-----------------------------------------------|
| `esp_now_hosted_slave.c` | Slave handlers: REQ→native `esp_now_*`, recv/send→async events. Self-registers via a `__constructor__`, so no edit to the stock `esp_hosted_coprocessor.c` is needed. |
| `esp_now_hosted_slave.h` | `esp_now_hosted_slave_init()` declaration |
| `esp_now_hosted_rpc.h`   | Wire protocol — **verbatim copy** of the host shim's; keep in sync |

## How it is applied

[`../apply-overlay.sh`](../apply-overlay.sh) injects this overlay into a
scaffolded `slave/` project with only safe appends:

1. copies the three sources into `slave/main/`;
2. registers `esp_now_hosted_slave.c` inside the existing
   `CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER` block in `main/CMakeLists.txt`;
3. adds `target_link_libraries(... "-u esp_now_hosted_slave_init")` so the linker
   keeps the object — the overlay self-registers from a constructor and nothing
   references its symbols, so it would otherwise be garbage-collected (the same
   fate as the stock `example_peer_data_transfer.c`);
4. appends `CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER=y` and
   `CONFIG_ESP_HOSTED_MAX_CUSTOM_MSG_HANDLERS=8` to `sdkconfig.defaults`.

It is idempotent and self-skips on ESP-Hosted < 2.8.1 (no CustomRpc channel).

## Wire-protocol coupling (important)

`esp_now_hosted_rpc.h` defines the exact bytes exchanged with the ESPHome host
shim (the `esp_now_hosted` half of the `esp32_hosted` component). The two copies
**must be byte-identical** — a mismatch silently corrupts every ESP-NOW frame.
When you revise the protocol, edit this copy **and** the host shim's copy
identically.

## Maintenance

Re-verify on each ESP-Hosted bump (see the design notes for the specifics):

- the CustomRpc callback signature (`esp_hosted_register_custom_callback` gained
  a 4th `void *local_context` arg around v2.8);
- the native `esp_now_send_cb_t` signature (changed to the `esp_now_send_info_t`
  form at IDF 5.5 — `esp_now_hosted_slave.c` version-guards it);
- that host/slave ESP-Hosted versions stay matched.

Retire the overlay if/when esp-hosted-mcu#19 lands native ESP-NOW over RPC.
