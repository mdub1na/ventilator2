// Short, bounded workloads for sensor attribution. No SMC access or hardware control.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <math.h>

static BOOL nominal(void) { return NSProcessInfo.processInfo.thermalState == NSProcessInfoThermalStateNominal; }

static NSDictionary *cpuWork(void) {
    double *results = calloc(2, sizeof(double));
    if (!results) return @{@"status":@"allocation-failed"};
    double start = NSDate.date.timeIntervalSince1970;
    double deadline = start + 10;
    dispatch_group_t group = dispatch_group_create();
    for (int worker = 0; worker < 2; worker++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            double value = 0.1 + worker;
            while (NSDate.date.timeIntervalSince1970 < deadline && nominal()) {
                for (int index = 0; index < 10000; index++) value = sin(value) + sqrt(fabs(value) + 1);
            }
            results[worker] = value;
        });
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    NSDictionary *result = @{@"phase":@"cpu", @"start":@(start),
        @"end":@(NSDate.date.timeIntervalSince1970), @"workers":@2,
        @"checksum":@(results[0] + results[1]), @"status":nominal() ? @"completed" : @"thermal-stop"};
    free(results);
    return result;
}

static NSDictionary *gpuWork(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return @{@"phase":@"gpu", @"status":@"unavailable"};
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void compute(device float *output [[buffer(0)]], uint i [[thread_position_in_grid]]) {"
        "float x = float(i % 1024) / 1024.0f + 0.01f;"
        "for (uint step = 0; step < 512; step++) x = fma(sin(x), 0.999f, 0.001f);"
        "output[i] = x;}";
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    id<MTLFunction> function = [library newFunctionWithName:@"compute"];
    id<MTLComputePipelineState> pipeline = function ? [device newComputePipelineStateWithFunction:function error:&error] : nil;
    id<MTLCommandQueue> queue = [device newCommandQueue];
    NSUInteger count = 262144;
    id<MTLBuffer> output = [device newBufferWithLength:count * sizeof(float) options:MTLResourceStorageModeShared];
    if (!pipeline || !queue || !output) return @{@"phase":@"gpu", @"status":@"setup-failed", @"error":error.localizedDescription ?: @"unknown"};
    double start = NSDate.date.timeIntervalSince1970;
    NSUInteger completed = 0;
    BOOL failed = NO;
    while (NSDate.date.timeIntervalSince1970 < start + 10 && nominal()) {
        @autoreleasepool {
            id<MTLCommandBuffer> command = [queue commandBuffer];
            id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
            if (!command || !encoder) { failed = YES; break; }
            [encoder setComputePipelineState:pipeline];
            [encoder setBuffer:output offset:0 atIndex:0];
            [encoder dispatchThreads:MTLSizeMake(count, 1, 1)
                threadsPerThreadgroup:MTLSizeMake(MIN(256, pipeline.maxTotalThreadsPerThreadgroup), 1, 1)];
            [encoder endEncoding];
            [command commit];
            [command waitUntilCompleted];
            if (command.status != MTLCommandBufferStatusCompleted) { failed = YES; break; }
            completed++;
        }
    }
    return @{@"phase":@"gpu", @"start":@(start), @"end":@(NSDate.date.timeIntervalSince1970),
        @"device":device.name, @"commandsCompleted":@(completed),
        @"status":failed ? @"command-failed" : (nominal() ? @"completed" : @"thermal-stop")};
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *phase = @(argv[1]);
        if (![phase isEqual:@"cpu"] && ![phase isEqual:@"gpu"]) return 2;
        NSDictionary *result = !nominal() ? @{@"phase":phase, @"status":@"thermal-stop"} :
            ([phase isEqual:@"cpu"] ? cpuWork() : gpuWork());
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
        if (!json) return 3;
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return [result[@"status"] isEqual:@"completed"] ? 0 : 1;
    }
}
