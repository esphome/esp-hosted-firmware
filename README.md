# ESP-Hosted Firmware

Pre-built [ESP-Hosted](https://github.com/espressif/esp-hosted) co-processor firmware binaries for use with ESPHome's [ESP32 Hosted](https://esphome.io/components/esp32_hosted/) component.

For full documentation, see the [ESP32 Hosted Update](https://esphome.io/components/update/esp32_hosted/) page.

## Supported Targets

Only targets supporting SDIO transport are built:

| Target | SDIO | Status |
|--------|:----:|--------|
| ESP32 | Yes | Built |
| ESP32-C5 | Yes | Built |
| ESP32-C6 | Yes | Built |
| ESP32-C61 | Yes | Built |

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

To build firmware locally, you'll need to set up the ESP-IDF environment:

```sh
# Clone and setup ESP-IDF
git clone -b v5.5.2 --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32c6  # or your target
source export.sh      # for Linux/macOS
export.bat            # for Windows
cd ..

# Create project from ESP-Hosted example
idf.py create-project-from-example "espressif/esp_hosted==2.9.3:slave"
cd slave/

# Build for your target
idf.py set-target esp32c6  # or your target
idf.py build

# Output: build/network_adapter.bin
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
