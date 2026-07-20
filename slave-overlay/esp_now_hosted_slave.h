/*
 * esp_now_hosted_slave — co-processor-side ESP-NOW handlers over esp-hosted
 * CustomRpc. Runs the native <esp_now.h> on the radio co-processor (e.g. an
 * ESP32-C6) and forwards frames/status to the radio-less host. Overlay onto the
 * esp-hosted `slave` example project.
 */

#ifndef ESP_NOW_HOSTED_SLAVE_H
#define ESP_NOW_HOSTED_SLAVE_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register the ESP-NOW-over-CustomRpc request handler on the co-processor.
 *
 * Registers ONE handler for ESP_NOW_HOSTED_MSG_REQ. Does NOT call esp_now_init();
 * that happens when the host sends ESP_NOW_HOSTED_OP_INIT (after the host has
 * brought Wi-Fi up via the normal proxied esp_wifi_* RPCs).
 *
 * Call once at slave start-up, next to example_peer_data_transfer_init() in
 * esp_hosted_coprocessor.c.
 *
 * @return ESP_OK on success
 */
esp_err_t esp_now_hosted_slave_init(void);

#ifdef __cplusplus
}
#endif

#endif /* ESP_NOW_HOSTED_SLAVE_H */
