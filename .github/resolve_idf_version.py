"""Print the ESP-IDF version ESPHome recommends for the host.

Reads the ``recommended`` entry of ``ESP_IDF_FRAMEWORK_VERSION_LOOKUP`` from
ESPHome's esp32 component on the dev branch without importing ESPHome.
"""

import ast
import sys
import urllib.request

URL = "https://raw.githubusercontent.com/esphome/esphome/dev/esphome/components/esp32/__init__.py"
NAME = "ESP_IDF_FRAMEWORK_VERSION_LOOKUP"


def main() -> None:
    with urllib.request.urlopen(URL) as resp:
        tree = ast.parse(resp.read())
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign) or not isinstance(node.value, ast.Dict):
            continue
        if not any(isinstance(t, ast.Name) and t.id == NAME for t in node.targets):
            continue
        for key, value in zip(node.value.keys, node.value.values):
            if isinstance(key, ast.Constant) and key.value == "recommended":
                print(".".join(str(arg.value) for arg in value.args))
                return
    sys.exit(f"{NAME}['recommended'] not found in {URL}")


if __name__ == "__main__":
    main()
