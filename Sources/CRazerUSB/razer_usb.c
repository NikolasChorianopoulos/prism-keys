#include "razer_usb.h"
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>

struct razer_usb_device {
    IOUSBDeviceInterface **iface;
};

static io_iterator_t find_devices(uint16_t vid, uint16_t pid) {
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    if (!match) return 0;
    int v = vid, p = pid;
    CFNumberRef vn = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &v);
    CFNumberRef pn = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &p);
    CFDictionarySetValue(match, CFSTR("idVendor"), vn);
    CFDictionarySetValue(match, CFSTR("idProduct"), pn);
    CFRelease(vn); CFRelease(pn);
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS) return 0;
    return it;
}

int razer_usb_count(uint16_t vid, uint16_t pid) {
    io_iterator_t it = find_devices(vid, pid);
    if (!it) return 0;
    int n = 0; io_service_t s;
    while ((s = IOIteratorNext(it))) { n++; IOObjectRelease(s); }
    IOObjectRelease(it);
    return n;
}

razer_usb_device *razer_usb_open(uint16_t vid, uint16_t pid) {
    io_iterator_t it = find_devices(vid, pid);
    if (!it) return NULL;
    io_service_t service = IOIteratorNext(it);
    IOObjectRelease(it);
    if (!service) return NULL;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
                                                         kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS || !plugin) return NULL;

    IOUSBDeviceInterface **iface = NULL;
    HRESULT res = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&iface);
    (*plugin)->Release(plugin);
    if (res || !iface) return NULL;

    razer_usb_device *dev = calloc(1, sizeof(*dev));
    dev->iface = iface;
    return dev;
}

void razer_usb_close(razer_usb_device *dev) {
    if (!dev) return;
    if (dev->iface) (*dev->iface)->Release(dev->iface);
    free(dev);
}

static int control(razer_usb_device *dev, uint8_t type, uint8_t request, uint16_t index, uint8_t *data, uint16_t len) {
    if (!dev || !dev->iface) return -1;
    IOUSBDevRequest req;
    req.bmRequestType = type;
    req.bRequest = request;
    req.wValue = 0x0300;      // report type Feature (3), report id 0
    req.wIndex = index;
    req.wLength = len;
    req.pData = data;
    req.wLenDone = 0;
    return (*dev->iface)->DeviceRequest(dev->iface, &req);
}

int razer_usb_set_report(razer_usb_device *dev, uint16_t index, const uint8_t *data, uint16_t len) {
    return control(dev, 0x21, 0x09, index, (uint8_t *)data, len);
}

int razer_usb_get_report(razer_usb_device *dev, uint16_t index, uint8_t *data, uint16_t len) {
    return control(dev, 0xA1, 0x01, index, data, len);
}

int razer_set_caps_lock(int on) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
    if (!s) return -1;
    io_connect_t c = 0;
    kern_return_t kr = IOServiceOpen(s, mach_task_self(), kIOHIDParamConnectType, &c);
    IOObjectRelease(s);
    if (kr != KERN_SUCCESS) return kr;
    kr = IOHIDSetModifierLockState(c, kIOHIDCapsLockState, on ? true : false);
    IOServiceClose(c);
    return kr;
}
