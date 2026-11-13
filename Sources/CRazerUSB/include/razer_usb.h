#ifndef RAZER_USB_H
#define RAZER_USB_H
#include <stdint.h>
#include <stddef.h>

/// Opaque handle to a USB device (default control pipe only; no exclusive open needed).
typedef struct razer_usb_device razer_usb_device;

/// Find the first USB device matching vendor/product. Returns NULL if not found.
razer_usb_device *razer_usb_open(uint16_t vendor_id, uint16_t product_id);
void razer_usb_close(razer_usb_device *dev);

/// HID class SET_REPORT (feature, report id 0) to the given interface. Returns 0 on success, IOReturn otherwise.
int razer_usb_set_report(razer_usb_device *dev, uint16_t interface_index, const uint8_t *data, uint16_t len);
/// HID class GET_REPORT (feature, report id 0). Returns 0 on success, IOReturn otherwise.
int razer_usb_get_report(razer_usb_device *dev, uint16_t interface_index, uint8_t *data, uint16_t len);

/// Returns the number of currently attached devices matching vendor/product.
int razer_usb_count(uint16_t vendor_id, uint16_t product_id);
#endif
