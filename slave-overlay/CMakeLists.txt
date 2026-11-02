# esp_hosted 3.x only: this directory is copied verbatim into the scaffolded
# project as components/esp_now_hosted/, which ESP-IDF discovers on its own.
# Nothing references the overlay's symbols (it self-registers from a
# constructor), so force the object into the link.
idf_component_register(
    SRCS          "esp_now_hosted_slave.c"
    INCLUDE_DIRS  "."
    REQUIRES      esp_hosted
    PRIV_REQUIRES esp_wifi
)
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u esp_now_hosted_slave_init")
