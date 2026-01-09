# ESP-Hosted Firmware

Pre-built [ESP-Hosted](https://github.com/espressif/esp-hosted) co-processor firmware binaries for use with ESPHome's [ESP32 Hosted](https://esphome.io/components/update/esp32_hosted/) component.

## Supported Targets

Only targets supporting SDIO transport are built:

| Target | SDIO | Status |
|--------|:----:|--------|
| ESP32 | Yes | Built |
| ESP32-C5 | Yes | Built |
| ESP32-C6 | Yes | Built |
| ESP32-C61 | Yes | Built |

## Usage

1. Download the appropriate firmware binary for your co-processor from the [GitHub Page](https://esphome.github.io/esp-hosted-firmware/).
2. Place the `.bin` file in your ESPHome configuration directory
3. Configure the update component in your ESPHome YAML:

```yaml
update:
  - platform: esp32_hosted
    firmware: coprocessor-firmware.bin
    # SHA256 hash from the .sha256 file
    expected_checksum: "abc123..."
```

## Building Locally

To build the firmware locally:

```bash
# Clone ESP-IDF
git clone -b v5.5.1 --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32c6  # or your target
source export.sh
cd ..

# Create project from ESP-Hosted example
idf.py create-project-from-example "espressif/esp_hosted==2.7.0:slave"
cd slave/

# Build for your target
idf.py set-target esp32c6  # or your target
idf.py build

# Output: build/network_adapter.bin
```

## Versioning

Releases are tagged with the ESP-Hosted version used (e.g., `v2.7.0`).

## License

The ESP-Hosted firmware is licensed under the Apache License 2.0. See the [ESP-Hosted repository](https://github.com/espressif/esp-hosted) for details.
