# ESP-Hosted Firmware

Pre-built [ESP-Hosted](https://github.com/espressif/esp-hosted) co-processor firmware binaries for use with ESPHome's [ESP32 Hosted](https://esphome.io/components/esp32_hosted/) component.

For full documentation, see the [ESP32 Hosted Update](https://esphome.io/components/update/esp32_hosted/) page.

## ESP-NOW support

These binaries are the stock ESP-Hosted slave **plus a small overlay that adds ESP-NOW to the host↔co-processor link**. Upstream ESP-Hosted proxies `esp_wifi.h` but not `esp_now.h` (Espressif tracking issue [esp-hosted-mcu#19](https://github.com/espressif/esp-hosted-mcu/issues/19)), so a radio-less host such as the ESP32-P4 cannot use ESP-NOW through the co-processor out of the box. The overlay bridges the native `esp_now_*` API over ESP-Hosted's CustomRpc channel, letting ESPHome's `espnow` component run unmodified on a hosted host. It was validated on real hardware (ESP32-P4 + ESP32-C6) on 2026-07-20.

The overlay lives in [`slave-overlay/`](slave-overlay/). On ESP-Hosted 2.x it is injected into each CI build by [`apply-overlay.sh`](apply-overlay.sh) and only applies to **≥ 2.8.1** (when the CustomRpc "peer data transfer" channel was added); older versions build as the unmodified stock slave. On ESP-Hosted 3.x the directory is a complete ESP-IDF component and is copied straight into the project's `components/`.

> **Wire-protocol coupling.** `slave-overlay/esp_now_hosted_rpc.h` is the on-the-wire contract and must stay byte-identical to the copy the ESPHome host shim (the `esp_now_hosted` half of the `esp32_hosted` component) uses. If the protocol changes, update **both** copies together.

## Supported Targets

Only targets supporting SDIO transport are built:

| Target | SDIO | Status |
|--------|:----:|--------|
| ESP32 | Yes | Built |
| ESP32-C5 | Yes | Built |
| ESP32-C6 | Yes | Built |
| ESP32-C61 | Yes | Built |

### ESP32-C5 partition table

ESP32-C5 co-processors that shipped with ESP-Hosted 2.x have their partition table at `0xc000`, not at the usual `0x8000`. An update through the host replaces only the firmware, and the firmware must be built for the offset of the table already on the chip. The ESP32-C5 images here are therefore built for `0xc000`, with the 2.x layout in [`partitions.esp32c5.csv`](partitions.esp32c5.csv).

> **Do not install the ESP32-C5 images of 3.0.8, 3.0.9, 3.0.10 or 3.1.0 built before this change over a 2.x co-processor.** They were built for `0x8000` and leave the co-processor unable to start. Recovery needs the ESP32-C5's own serial port: erase the `otadata` partition (`esptool --chip esp32c5 erase-region 0x16000 0x2000`) and it boots the previous firmware again.

A co-processor that was flashed over its serial port with a stock ESP-Hosted 3.x build has its table at `0x8000`. Do not install the ESP32-C5 images from here on it.

## Usage

Pre-built firmware binaries and manifests are available at [esphome.github.io/esp-hosted-firmware](https://esphome.github.io/esp-hosted-firmware/).

### HTTP Mode (Recommended)

Automatically fetch and update firmware from the manifest:

```yaml
http_request:

update:
  - platform: esp32_hosted
    type: http
    source: https://esphome.github.io/esp-hosted-firmware/manifest/esp32c6.json
    update_interval: 6h
```

### Embedded Mode

Embed the firmware binary into your device's flash:

1. Download the firmware binary from the [GitHub Page](https://esphome.github.io/esp-hosted-firmware/)
2. Place the `.bin` file in your ESPHome configuration directory
3. Generate the SHA256 hash (see below)
4. Configure the update component:

```yaml
update:
  - platform: esp32_hosted
    type: embedded
    path: network_adapter_esp32c6.bin
    sha256: de2f256064a0af797747c2b97505dc0b9f3df0de4f489eac731c23ae9ca9cc31
```

## Building Custom Firmware

To build firmware locally, you'll need to set up the ESP-IDF environment. Use
the ESP-IDF release that ESPHome recommends for the host, which is what CI
builds with:

```sh
# Clone and setup ESP-IDF
git clone -b vx.y.z --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32c6  # or your target
source export.sh      # for Linux/macOS
export.bat            # for Windows
cd ..

# Create project from ESP-Hosted example
idf.py create-project-from-example "espressif/esp_hosted==2.9.3:slave"

# Inject the ESP-NOW overlay (no-op on ESP-Hosted < 2.8.1)
./apply-overlay.sh slave

cd slave/

# Build for your target
idf.py set-target esp32c6  # or your target
idf.py build

# Output: build/network_adapter.bin
```

To build the *stock* slave without ESP-NOW, simply skip the `apply-overlay.sh` step.

For ESP-Hosted 3.x there is no `slave` example. The equivalent Wi-Fi + BT (VHCI)
co-processor project is `bluetooth/esp_hosted_nimble/bleprph_wifi_coex/cp`
(3.0.6 and newer; earlier 3.x releases are not supported), which produces
`build/eh_cp_bt_wifi_hosted_hci_mcu.bin`. 3.x needs ESP-IDF 5.5 or newer (CI
uses the release ESPHome recommends). The ESP-NOW overlay applies to 3.x too:
`slave-overlay/` is a complete ESP-IDF component there, so instead of running
`apply-overlay.sh` just copy it into the project's `components/` directory.

```sh
idf.py create-project-from-example --path coprocessor "espressif/esp_hosted==3.0.8:bluetooth/esp_hosted_nimble/bleprph_wifi_coex/cp"
mkdir -p coprocessor/components
cp -r slave-overlay coprocessor/components/esp_now_hosted
cd coprocessor/
idf.py set-target esp32c6
idf.py build
```

After building, copy the firmware to your ESPHome configuration directory:

```sh
cp build/network_adapter.bin /path/to/your/esphome/config/
```

### Generating SHA256 Hash

For embedded mode, you need the SHA256 hash of your firmware binary:

```sh
# Linux/macOS
sha256sum network_adapter.bin

# Windows PowerShell
Get-FileHash -Algorithm SHA256 network_adapter.bin

# Windows Command Prompt
certutil -hashfile network_adapter.bin SHA256
```

## Versioning

Releases are tagged with the ESP-Hosted version used (e.g., `v2.7.0`).

## License

The ESP-Hosted firmware is licensed under the Apache License 2.0. See the [ESP-Hosted repository](https://github.com/espressif/esp-hosted) for details.
