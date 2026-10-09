#import <Foundation/Foundation.h>
#include "HIDTemperatureRead.h"
#include <mach/mach_time.h>
#include <math.h>
#include <sys/sysctl.h>
#include <unistd.h>

static NSString *system_string(const char *name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) || size < 2) return @"unknown";
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (sysctlbyname(name, data.mutableBytes, &size, NULL, 0)) return @"unknown";
    return [NSString stringWithUTF8String:data.bytes] ?: @"unknown";
}

static NSDictionary *profile(void) {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    return @{@"model": system_string("hw.model"), @"build": system_string("kern.osversion"),
             @"version": [NSString stringWithFormat:@"%ld.%ld.%ld", os.majorVersion, os.minorVersion, os.patchVersion]};
}

static double seconds(void) {
    mach_timebase_info_data_t info = {0};
    if (mach_timebase_info(&info) != KERN_SUCCESS || !info.denom) return NAN;
    return (double)((long double)mach_continuous_time() * info.numer / info.denom / 1e9L);
}

// This executable links only the existing NAND reader. No SMC transport, load or helper RPC.
int main(int argc, const char **argv) {
    (void)argv;
    @autoreleasepool {
        if (argc != 1 || geteuid() == 0) return 78;
        NSDictionary *expected = @{@"model": @"Mac15,7", @"version": @"27.0.1", @"build": @"26A434"};
        NSDictionary *before = profile();
        NSMutableArray *samples = [NSMutableArray array];
        BOOL passed = [before isEqual:expected];
        double started = seconds();
        passed = passed && isfinite(started);
        if (passed) {
            for (int index = 0; index < 5; index++) {
                double celsius = NAN, began = seconds();
                int32_t status = HIDTemperatureReadNAND(&celsius);
                double ended = seconds(), elapsed = ended - began;
                BOOL timely = isfinite(elapsed) && elapsed >= 0 && elapsed < 0.5;
                BOOL valid = status == 0 && isfinite(celsius) && celsius >= -10 && celsius <= 125 && timely;
                [samples addObject:@{@"index": @(index), @"status": @(status),
                    @"celsius": isfinite(celsius) ? @(celsius) : NSNull.null,
                    @"readSeconds": isfinite(elapsed) ? @(elapsed) : NSNull.null,
                    @"elapsedSeconds": isfinite(ended - started) ? @(ended - started) : NSNull.null,
                    @"accepted": @(valid)}];
                if (!valid) { passed = NO; break; }
                if (index < 4) usleep(1000000);
            }
        }
        NSDictionary *after = profile();
        passed = passed && samples.count == 5 && [before isEqual:after];
        NSDictionary *report = @{@"profileBefore": before, @"profileAfter": after, @"samples": samples,
            @"passed": @(passed), @"SMCTransportLinked": @NO, @"hardwareWrites": @0,
            @"source": @"NAND CH0 temp / TN0n / AppleEmbeddedNVMeTemperatureSensor / AppleANS3CGv2Controller"};
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        if (!json || fwrite(json.bytes, 1, json.length, stdout) != json.length) return 78;
        putchar('\n');
        return passed ? 0 : 78;
    }
}
