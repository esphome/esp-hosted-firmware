/*
 * esp_now_hosted_slave — co-processor-side implementation.
 *
 * Adds ESP-NOW to the esp-hosted host<->co-processor link that Espressif's RPC
 * layer does NOT proxy (tracking issue espressif/esp-hosted-mcu#19). ESP-NOW
 * itself is fully supported natively on the co-processor; this file only bridges
 * it over CustomRpc:
 *
 *   host ESP_NOW_HOSTED_MSG_REQ --> slave_req_cb --> native esp_now_*()  (reply: RESP)
 *   native recv cb              --> ESP_NOW_HOSTED_MSG_RECV event --> host
 *   native send cb              --> ESP_NOW_HOSTED_MSG_SEND event --> host
 *
 * Overlay this file onto the esp-hosted `slave` example (see README.md) and add
 * a single call to esp_now_hosted_slave_init() at slave start-up.
 */

#include <string.h>

#include "esp_err.h"
#include "esp_idf_version.h"
#include "esp_log.h"
#include "esp_now.h"   /* NATIVE ESP-NOW on the co-processor */
#include "esp_wifi.h"

#include "esp_hosted_peer_data.h"  /* esp_hosted_{send_custom_data,register_custom_callback} */

#include "esp_now_hosted_slave.h"
#include "esp_now_hosted_rpc.h"

static const char *TAG = "esp_now_hosted";

/* ── Native ESP-NOW callbacks (run in the co-processor Wi-Fi task) → events ───
 * esp_hosted_send_custom_data() enqueues onto the RPC TX path; safe to call
 * from the Wi-Fi task. Frames are <= ESP_NOW_HOSTED_MAX_FRAME, well under the
 * 8166 B CustomRpc cap.                                                        */

static void slave_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
  if (len < 0 || len > (int) ESP_NOW_HOSTED_MAX_FRAME)
    return;
  uint8_t buf[sizeof(esp_now_hosted_recv_evt_t) + ESP_NOW_HOSTED_MAX_FRAME];
  esp_now_hosted_recv_evt_t *e = (esp_now_hosted_recv_evt_t *) buf;
  memcpy(e->src_addr, info->src_addr, 6);
  memcpy(e->des_addr, info->des_addr, 6);
  e->rssi = info->rx_ctrl ? info->rx_ctrl->rssi : 0;
  e->channel = info->rx_ctrl ? info->rx_ctrl->channel : 0;
  e->data_len = (uint16_t) len;
  memcpy(e->data, data, len);
  esp_hosted_send_custom_data(ESP_NOW_HOSTED_MSG_RECV, buf, sizeof(*e) + len);
}

#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 5, 0)
static void slave_send_cb(const esp_now_send_info_t *tx_info, esp_now_send_status_t status) {
  esp_now_hosted_send_evt_t e;
  memcpy(e.des_addr, tx_info->des_addr, 6);
  e.status = (uint8_t) status;
  esp_hosted_send_custom_data(ESP_NOW_HOSTED_MSG_SEND, (const uint8_t *) &e, sizeof(e));
}
#else
static void slave_send_cb(const uint8_t *mac_addr, esp_now_send_status_t status) {
  esp_now_hosted_send_evt_t e;
  memcpy(e.des_addr, mac_addr, 6);
  e.status = (uint8_t) status;
  esp_hosted_send_custom_data(ESP_NOW_HOSTED_MSG_SEND, (const uint8_t *) &e, sizeof(e));
}
#endif

/* ── Request handler (runs in the co-processor RPC RX thread — keep it fast) ──
 * All esp_now_* calls below are non-blocking (esp_now_send only enqueues).     */

static void slave_req_cb(uint32_t msg_id, const uint8_t *data, size_t len, void *ctx) {
  (void) msg_id;
  (void) ctx;
  if (len < sizeof(esp_now_hosted_req_t))
    return;
  const esp_now_hosted_req_t *req = (const esp_now_hosted_req_t *) data;
  if (len < sizeof(esp_now_hosted_req_t) + req->payload_len)
    return;

  uint8_t rbuf[sizeof(esp_now_hosted_resp_t) + 8];
  esp_now_hosted_resp_t *resp = (esp_now_hosted_resp_t *) rbuf;
  resp->opcode = req->opcode;
  resp->seq = req->seq;
  resp->status = ESP_OK;
  resp->ret_len = 0;
  size_t resp_len = sizeof(esp_now_hosted_resp_t);

  const uint8_t *pl = req->payload;
  const uint16_t pl_len = req->payload_len;

  switch (req->opcode) {
    case ESP_NOW_HOSTED_OP_INIT:
      resp->status = esp_now_init();
      if (resp->status == ESP_OK) {
        esp_now_register_recv_cb(slave_recv_cb);
        esp_now_register_send_cb(slave_send_cb);
      }
      break;

    case ESP_NOW_HOSTED_OP_DEINIT:
      esp_now_unregister_recv_cb();
      esp_now_unregister_send_cb();
      resp->status = esp_now_deinit();
      break;

    case ESP_NOW_HOSTED_OP_GET_VERSION: {
      uint32_t v = 0;
      resp->status = esp_now_get_version(&v);
      memcpy(resp->ret, &v, sizeof(v));
      resp->ret_len = sizeof(v);
      resp_len += sizeof(v);
      break;
    }

    case ESP_NOW_HOSTED_OP_ADD_PEER:
    case ESP_NOW_HOSTED_OP_MOD_PEER: {
      if (pl_len < sizeof(esp_now_hosted_peer_t)) {
        resp->status = ESP_ERR_INVALID_SIZE;
        break;
      }
      const esp_now_hosted_peer_t *p = (const esp_now_hosted_peer_t *) pl;
      esp_now_peer_info_t pi;
      memset(&pi, 0, sizeof(pi));
      memcpy(pi.peer_addr, p->peer_addr, 6);
      memcpy(pi.lmk, p->lmk, 16);
      pi.channel = p->channel;
      pi.ifidx = (wifi_interface_t) p->ifidx;
      pi.encrypt = p->encrypt ? true : false;
      resp->status = (req->opcode == ESP_NOW_HOSTED_OP_ADD_PEER) ? esp_now_add_peer(&pi)
                                                                 : esp_now_mod_peer(&pi);
      break;
    }

    case ESP_NOW_HOSTED_OP_DEL_PEER:
      if (pl_len < 6) {
        resp->status = ESP_ERR_INVALID_SIZE;
        break;
      }
      resp->status = esp_now_del_peer(pl);
      break;

    case ESP_NOW_HOSTED_OP_IS_PEER_EXIST: {
      if (pl_len < 6) {
        resp->status = ESP_ERR_INVALID_SIZE;
        break;
      }
      resp->ret[0] = esp_now_is_peer_exist(pl) ? 1 : 0;
      resp->ret_len = 1;
      resp_len += 1;
      resp->status = ESP_OK;
      break;
    }

    case ESP_NOW_HOSTED_OP_SEND: {
      if (pl_len < sizeof(esp_now_hosted_send_req_t)) {
        resp->status = ESP_ERR_INVALID_SIZE;
        break;
      }
      const esp_now_hosted_send_req_t *s = (const esp_now_hosted_send_req_t *) pl;
      /* data_len is host-supplied; bound it against the bytes actually received
       * (pl_len minus the fixed header) and the protocol frame cap before
       * handing the pointer to esp_now_send, which would otherwise read past
       * the request buffer. */
      const size_t avail = pl_len - sizeof(esp_now_hosted_send_req_t);
      if (s->data_len > avail || s->data_len > ESP_NOW_HOSTED_MAX_FRAME) {
        resp->status = ESP_ERR_INVALID_SIZE;
        break;
      }
      const uint8_t *addr = s->has_addr ? s->peer_addr : NULL;
      resp->status = esp_now_send(addr, s->data, s->data_len);
      break;
    }

    case ESP_NOW_HOSTED_OP_SET_PMK:
      if (pl_len < 16) {
        resp->status = ESP_ERR_INVALID_SIZE;
        break;
      }
      resp->status = esp_now_set_pmk(pl);
      break;

    default:
      resp->status = ESP_ERR_NOT_SUPPORTED;
      break;
  }

  esp_hosted_send_custom_data(ESP_NOW_HOSTED_MSG_RESP, rbuf, resp_len);
}

esp_err_t esp_now_hosted_slave_init(void) {
  esp_err_t err = esp_hosted_register_custom_callback(ESP_NOW_HOSTED_MSG_REQ, slave_req_cb, NULL);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "failed to register ESP-NOW CustomRpc handler: 0x%x", err);
    return err;
  }
  ESP_LOGI(TAG, "ESP-NOW-hosted CustomRpc handler registered (awaiting host INIT)");
  return err;
}

/* Self-registration so the overlay needs no edit to the stock
 * esp_hosted_coprocessor.c. esp_now_hosted_slave_init() only registers a
 * CustomRpc callback (fills a static handler slot + creates a mutex — no
 * transport, Wi-Fi, or heap-hungry work), so running it from a constructor
 * before app_main is safe.
 *
 * IMPORTANT: nothing references this object's symbols, so the linker would
 * garbage-collect the whole translation unit (and this constructor with it) —
 * exactly what happens to the stock example_peer_data_transfer.c. apply-overlay.sh
 * therefore also adds `-u esp_now_hosted_slave_init` to main/CMakeLists.txt to
 * force the object into the link. Without that flag this constructor never runs.
 *
 * If a future esp_hosted makes init unsafe this early, drop this constructor and
 * call esp_now_hosted_slave_init() next to example_peer_data_transfer_init() in
 * esp_hosted_coprocessor.c instead. */
static void __attribute__((constructor)) esp_now_hosted_autoreg(void) {
  esp_now_hosted_slave_init();
}
