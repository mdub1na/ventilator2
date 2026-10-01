#include "HIDTemperatureRead.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <math.h>
#include <string.h>

// These four symbols are private ABI, resolved optionally. Keep the boundary here.
typedef IOHIDEventSystemClientRef (*CreateClient)(CFAllocatorRef);
typedef CFTypeRef (*CopyEvent)(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
typedef double (*FloatValue)(CFTypeRef, int32_t);
typedef uint64_t (*Timestamp)(CFTypeRef);

static int string_property_equals(IOHIDServiceClientRef service, CFStringRef key, CFStringRef expected) {
    CFTypeRef property = IOHIDServiceClientCopyProperty(service, key);
    int matches = property && CFGetTypeID(property) == CFStringGetTypeID() && CFEqual(property, expected);
    if (property) CFRelease(property);
    return matches;
}

static int is_local_nand(IOHIDServiceClientRef service) {
    if (!IOHIDServiceClientConformsTo(service, 0xff00, 5) ||
        !string_property_equals(service, CFSTR("Product"), CFSTR("NAND CH0 temp"))) return 0;
    CFTypeRef location = IOHIDServiceClientCopyProperty(service, CFSTR("LocationID"));
    int64_t code = 0;
    int matches = location && CFGetTypeID(location) == CFNumberGetTypeID() &&
        CFNumberGetValue((CFNumberRef)location, kCFNumberSInt64Type, &code) && code == 0x544e306e; // TN0n
    if (location) CFRelease(location);
    if (!matches) return 0;
    CFTypeRef registryID = IOHIDServiceClientGetRegistryID(service); // Borrowed.
    int64_t identifier = 0;
    if (!registryID || CFGetTypeID(registryID) != CFNumberGetTypeID() ||
        !CFNumberGetValue((CFNumberRef)registryID, kCFNumberSInt64Type, &identifier)) return 0;
    io_registry_entry_t entry = IOServiceGetMatchingService(kIOMainPortDefault,
        IORegistryEntryIDMatching((uint64_t)identifier));
    if (!entry) return 0;
    io_name_t driver = {0}, controller = {0};
    io_registry_entry_t parent = 0;
    matches = IOObjectGetClass(entry, driver) == KERN_SUCCESS &&
        strcmp(driver, "AppleEmbeddedNVMeTemperatureSensor") == 0 &&
        IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS &&
        IOObjectGetClass(parent, controller) == KERN_SUCCESS &&
        strcmp(controller, "AppleANS3CGv2Controller") == 0;
    if (parent) IOObjectRelease(parent);
    IOObjectRelease(entry);
    return matches;
}

int32_t HIDTemperatureReadNAND(double *celsius) {
    if (!celsius) return -1;
    *celsius = NAN;
    int32_t status = -2;
    void *framework = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!framework) return status;
    CreateClient create = (CreateClient)dlsym(framework, "IOHIDEventSystemClientCreate");
    CopyEvent copy = (CopyEvent)dlsym(framework, "IOHIDServiceClientCopyEvent");
    FloatValue number = (FloatValue)dlsym(framework, "IOHIDEventGetFloatValue");
    Timestamp timestamp = (Timestamp)dlsym(framework, "IOHIDEventGetTimeStamp");
    IOHIDEventSystemClientRef client = create && copy && number && timestamp ? create(kCFAllocatorDefault) : NULL;
    CFArrayRef services = client ? IOHIDEventSystemClientCopyServices(client) : NULL;
    if (services) {
        IOHIDServiceClientRef selected = NULL;
        int count = 0;
        for (CFIndex index = 0; index < CFArrayGetCount(services); index++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
            if (is_local_nand(service)) { selected = service; count++; }
        }
        status = count == 1 ? -4 : -3;
        CFTypeRef event = count == 1 ? copy(selected, 15, 0, 0) : NULL;
        if (event) {
            double value = number(event, 15 << 16);
            uint64_t measured = timestamp(event), now = mach_absolute_time();
            mach_timebase_info_data_t timebase = {0};
            status = -5;
            if (mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.denom && measured && now >= measured) {
                long double age = (long double)(now - measured) * timebase.numer / timebase.denom / 1e9L;
                if (age <= 2 && isfinite(value)) { *celsius = value; status = 0; }
            }
            CFRelease(event);
        }
        CFRelease(services);
    }
    if (client) CFRelease(client);
    dlclose(framework);
    return status;
}
