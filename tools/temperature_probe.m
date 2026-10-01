// Research utility: enumerates and reads temperature services/SMC keys. No hardware writes.
// Build with scripts/build-temperature-probe.sh. Output is one JSON object per sample.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>
#include "SMCRead.h"
#include <dlfcn.h>
#include <math.h>
#include <sys/sysctl.h>
#include <unistd.h>

typedef CFTypeRef (*CopyEventFunction)(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
typedef double (*EventFloatFunction)(CFTypeRef, int32_t);
typedef uint64_t (*EventTimestampFunction)(CFTypeRef);
typedef IOHIDEventSystemClientRef (*CreateClientFunction)(CFAllocatorRef);

static NSString *fourcc(uint32_t code) {
    char text[5] = {(char)(code >> 24), (char)(code >> 16), (char)(code >> 8), (char)code, 0};
    return [[NSString alloc] initWithBytes:text length:4 encoding:NSASCIIStringEncoding] ?: @"????";
}

static NSString *sysctlText(const char *name) {
    size_t length = 0;
    if (sysctlbyname(name, NULL, &length, NULL, 0) != 0 || length < 2) return @"unavailable";
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (sysctlbyname(name, data.mutableBytes, &length, NULL, 0) != 0) return @"unavailable";
    return [NSString stringWithUTF8String:data.bytes] ?: @"unavailable";
}

static NSArray *serviceAncestry(NSNumber *registryID) {
    io_registry_entry_t entry = IOServiceGetMatchingService(kIOMainPortDefault,
        IORegistryEntryIDMatching(registryID.unsignedLongLongValue));
    NSMutableArray *rows = [NSMutableArray array];
    for (int depth = 0; entry && depth < 12; depth++) {
        io_name_t className = {0}, name = {0};
        IOObjectGetClass(entry, className);
        IORegistryEntryGetName(entry, name);
        [rows addObject:@{@"class":@(className), @"name":@(name)}];
        io_registry_entry_t parent = 0;
        IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
        IOObjectRelease(entry);
        entry = parent;
    }
    if (entry) IOObjectRelease(entry);
    return rows;
}

static id numberForValue(SMCReadValue value) {
    if (value.type == 0x666c7420 && value.size == 4) { // flt
        float result;
        memcpy(&result, value.bytes, sizeof(result));
        return isfinite(result) ? @(result) : (id)[NSNull null];
    }
    if (value.type == 0x73703738 && value.size == 2) { // sp78
        int16_t raw = (int16_t)(((uint16_t)value.bytes[0] << 8) | value.bytes[1]);
        return @(raw / 256.0);
    }
    return [NSNull null];
}

static NSArray<NSString *> *temperatureKeys(SMCReadConnection *connection) {
    SMCReadValue countValue = {0};
    if (!connection || SMCReadKey(connection, "#KEY", &countValue) != 0 ||
        countValue.type != 0x75693332 || countValue.size != 4) return @[];
    uint32_t count = ((uint32_t)countValue.bytes[0] << 24) |
                     ((uint32_t)countValue.bytes[1] << 16) |
                     ((uint32_t)countValue.bytes[2] << 8) | countValue.bytes[3];
    NSMutableArray *keys = [NSMutableArray array];
    for (uint32_t index = 0; index < MIN(count, 10000); index++) {
        char key[5] = {0};
        if (SMCReadKeyNameAtIndex(connection, index, key) == 0 && key[0] == 'T') {
            NSString *name = [[NSString alloc] initWithBytes:key length:4 encoding:NSASCIIStringEncoding];
            if (name) [keys addObject:name];
        }
    }
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

static NSArray *readSMC(SMCReadConnection *connection, NSArray<NSString *> *keys) {
    NSMutableArray *readings = [NSMutableArray array];
    for (NSString *key in keys) {
        SMCReadValue value = {0};
        int status = SMCReadKey(connection, key.UTF8String, &value);
        if (status != 0) {
            [readings addObject:@{@"key":key, @"error":@(status)}];
            continue;
        }
        id number = numberForValue(value);
        NSMutableString *bytes = [NSMutableString string];
        for (uint32_t index = 0; index < value.size; index++) [bytes appendFormat:@"%02x", value.bytes[index]];
        [readings addObject:@{@"key":key, @"type":fourcc(value.type), @"size":@(value.size),
                             @"rawHex":bytes, @"value":number}];
    }
    return readings;
}

static NSArray *readHID(IOHIDEventSystemClientRef client, CopyEventFunction copyEvent,
                       EventFloatFunction floatValue, EventTimestampFunction timestamp) {
    if (!client || !copyEvent || !floatValue) return @[];
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) return @[];
    NSMutableArray *readings = [NSMutableArray array];
    for (CFIndex index = 0; index < CFArrayGetCount(services); index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        if (!IOHIDServiceClientConformsTo(service, 0xff00, 5)) continue;
        id product = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        id location = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("LocationID")));
        id registryID = (__bridge id)IOHIDServiceClientGetRegistryID(service);
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        row[@"product"] = [product isKindOfClass:NSString.class] ? product : @"unnamed";
        if ([registryID isKindOfClass:NSNumber.class]) {
            row[@"registryID"] = registryID;
            row[@"ancestry"] = serviceAncestry(registryID);
        }
        if ([location isKindOfClass:NSNumber.class]) {
            row[@"locationID"] = location;
            row[@"locationFourCC"] = fourcc([location unsignedIntValue]);
        }
        CFTypeRef event = copyEvent(service, 15, 0, 0); // Temperature event, field base 15 << 16.
        if (event) {
            double celsius = floatValue(event, 15 << 16);
            row[@"value"] = isfinite(celsius) ? @(celsius) : (id)[NSNull null];
            if (timestamp) row[@"eventTimestamp"] = @(timestamp(event));
            CFRelease(event);
        } else {
            row[@"value"] = [NSNull null];
        }
        [readings addObject:row];
    }
    CFRelease(services);
    return [readings sortedArrayUsingDescriptors:@[
        [NSSortDescriptor sortDescriptorWithKey:@"product" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"registryID" ascending:YES]
    ]];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        int samples = argc > 1 ? atoi(argv[1]) : 1;
        if (samples < 1 || samples > 120) return 2;
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        CopyEventFunction copyEvent = iokit ? (CopyEventFunction)dlsym(iokit, "IOHIDServiceClientCopyEvent") : NULL;
        EventFloatFunction floatValue = iokit ? (EventFloatFunction)dlsym(iokit, "IOHIDEventGetFloatValue") : NULL;
        EventTimestampFunction timestamp = iokit ? (EventTimestampFunction)dlsym(iokit, "IOHIDEventGetTimeStamp") : NULL;
        CreateClientFunction createClient = iokit ? (CreateClientFunction)dlsym(iokit, "IOHIDEventSystemClientCreate") : NULL;
        IOHIDEventSystemClientRef client = createClient ? createClient(kCFAllocatorDefault) : NULL;
        SMCReadConnection *smc = SMCReadOpen();
        NSArray *keys = temperatureKeys(smc);
        for (int index = 0; index < samples; index++) {
            @autoreleasepool {
                NSDictionary *result = @{
                    @"sample":@(index), @"time":@([NSDate.date timeIntervalSince1970]),
                    @"model":sysctlText("hw.model"), @"macOSBuild":sysctlText("kern.osversion"),
                    @"thermalState":@(NSProcessInfo.processInfo.thermalState),
                    @"hidClientAvailable":@(client != NULL),
                    @"hidClientKind":@"event-system",
                    @"hidEventAPIAvailable":@(copyEvent != NULL && floatValue != NULL),
                    @"smcAvailable":@(smc != NULL),
                    @"hid":readHID(client, copyEvent, floatValue, timestamp),
                    @"smc":readSMC(smc, keys)
                };
                NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
                if (!json) return 3;
                fwrite(json.bytes, 1, json.length, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            }
            if (index + 1 < samples) sleep(1);
        }
        SMCReadClose(smc);
        if (client) CFRelease(client);
        if (iokit) dlclose(iokit);
    }
    return 0;
}
