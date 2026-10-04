#include "SMCExperiment.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } Limits;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct {
    uint32_t key; Version version; Limits limits; KeyInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} Packet;
_Static_assert(sizeof(Packet) == 80, "Unexpected SMC ABI");

struct SMCExperimentConnection {
    io_connect_t port;
    double deadline, unlockedAt;
    uint16_t attempted;
    uint32_t nextFixed;
    int restorationOnly, fixedClosed;
};

static uint32_t code(const char *value) {
    return (uint32_t)(uint8_t)value[0] << 24 | (uint32_t)(uint8_t)value[1] << 16 |
           (uint32_t)(uint8_t)value[2] << 8 | (uint8_t)value[3];
}
static double clock_now(void) {
    mach_timebase_info_data_t base;
    if (mach_timebase_info(&base) != KERN_SUCCESS || !base.denom) return NAN;
    return (double)mach_continuous_time() * base.numer / base.denom / 1e9;
}
static int identity_matches(void) {
    char model[32] = {0}, build[32] = {0};
    size_t modelSize = sizeof(model), buildSize = sizeof(build);
    return sysctlbyname("hw.model", model, &modelSize, NULL, 0) == 0 &&
           sysctlbyname("kern.osversion", build, &buildSize, NULL, 0) == 0 &&
           strcmp(model, "Mac15,7") == 0 && strcmp(build, "26A434") == 0;
}

int32_t SMCExperimentDescribeStep(uint32_t step, SMCExperimentStep *description) {
    if (!description || step > 9) return -1;
    static const char *keys[] = {"Ftst", "F0Md", "F1Md", "F0Tg", "F1Tg",
                                 "F0Md", "F1Md", "F0Tg", "F1Tg", "Ftst"};
    memset(description, 0, sizeof(*description));
    memcpy(description->key, keys[step], 5);
    int isFloat = step == 3 || step == 4 || step == 7 || step == 8;
    description->type = code(isFloat ? "flt " : "ui8 ");
    description->size = isFloat ? 4 : 1;
    if (step <= 2) description->payload[0] = 1;
    if (step == 3 || step == 4) {
        // IEEE-754 little-endian 2500.0, independently compared with the review plan in tests.
        const uint8_t target[4] = {0x00, 0x40, 0x1c, 0x45};
        memcpy(description->payload, target, 4);
    }
    return 0;
}

int32_t SMCExperimentBuildRequest(uint32_t step, uint32_t actualType, uint32_t actualSize,
                                  SMCExperimentRequest *request) {
    if (!request) return -1;
    memset(request, 0, sizeof(*request));
    SMCExperimentStep description;
    if (SMCExperimentDescribeStep(step, &description) != 0) return -1;
    if (description.type != actualType || description.size != actualSize) return -2;
    Packet packet = {0};
    packet.key = code(description.key);
    packet.info.size = description.size;
    packet.command = 6;
    memcpy(packet.bytes, description.payload, description.size);
    memcpy(request, &packet, sizeof(packet));
    return 0;
}

int32_t SMCExperimentValidateReply(int32_t kernelStatus, uint32_t size, const SMCExperimentRequest *reply,
                                   SMCExperimentResult *result) {
    if (!reply || !result) return -1;
    memset(result, 0, sizeof(*result));
    result->kernelStatus = kernelStatus;
    if (kernelStatus != KERN_SUCCESS || size != sizeof(Packet)) return -2;
    Packet packet;
    memcpy(&packet, reply, sizeof(packet));
    result->smcResult = packet.result;
    result->smcStatus = packet.status;
    if (packet.result != 0) return -3;
    // No nonzero status has been qualified for this experimental writer.
    return packet.status == 0 ? 0 : -4;
}

static int call(io_connect_t port, Packet *input, Packet *output, SMCExperimentResult *result) {
    size_t size = sizeof(*output);
    memset(output, 0, size);
    kern_return_t status = IOConnectCallStructMethod(port, 2, input, sizeof(*input), output, &size);
    return SMCExperimentValidateReply(status, (uint32_t)size, (SMCExperimentRequest *)output, result);
}

static int read_value(SMCExperimentConnection *connection, const char *key, uint32_t expectedType,
                       uint32_t expectedSize, Packet *value) {
    Packet request = {0}, metadata = {0};
    SMCExperimentResult result;
    request.key = code(key); request.command = 9;
    if (call(connection->port, &request, &metadata, &result) != 0 ||
        metadata.info.type != expectedType || metadata.info.size != expectedSize) return 0;
    request.command = 5; request.info.size = expectedSize;
    return call(connection->port, &request, value, &result) == 0;
}
static int read_byte(SMCExperimentConnection *connection, const char *key, uint8_t *value) {
    Packet packet;
    if (!read_value(connection, key, code("ui8 "), 1, &packet)) return 0;
    *value = packet.bytes[0]; return 1;
}
static int read_rpm(SMCExperimentConnection *connection, const char *key, float *value) {
    Packet packet;
    if (!read_value(connection, key, code("flt "), 4, &packet)) return 0;
    uint32_t bits = (uint32_t)packet.bytes[0] | (uint32_t)packet.bytes[1] << 8 |
                    (uint32_t)packet.bytes[2] << 16 | (uint32_t)packet.bytes[3] << 24;
    memcpy(value, &bits, sizeof(bits));
    return isfinite(*value) && *value >= 0;
}

static int prerequisites(SMCExperimentConnection *connection, uint32_t step) {
    uint8_t count, modes[2], test;
    if (!read_byte(connection, "FNum", &count) || count != 2 ||
        !read_byte(connection, "F0Md", &modes[0]) || !read_byte(connection, "F1Md", &modes[1]) ||
        !read_byte(connection, "Ftst", &test)) return 0;
    if (step >= 5) {
        if (step == 7) return modes[0] == 0 || modes[0] == 3;
        if (step == 8) return modes[1] == 0 || modes[1] == 3;
        if (step == 9) return (modes[0] == 0 || modes[0] == 3) && (modes[1] == 0 || modes[1] == 3);
        return 1; // Restore a known fan even if the other fan's mode is unexpected.
    }
    float lower[2], upper[2];
    if (!read_rpm(connection, "F0Mn", &lower[0]) || !read_rpm(connection, "F0Mx", &upper[0]) ||
        !read_rpm(connection, "F1Mn", &lower[1]) || !read_rpm(connection, "F1Mx", &upper[1]) ||
        lower[0] != 1350 || upper[0] != 5349 || lower[1] != 1458 || upper[1] != 5777) return 0;
    if (step == 0) {
        float actual0, actual1, target0, target1;
        return test == 0 && modes[0] == 3 && modes[1] == 3 &&
               read_rpm(connection, "F0Ac", &actual0) && read_rpm(connection, "F1Ac", &actual1) &&
               read_rpm(connection, "F0Tg", &target0) && read_rpm(connection, "F1Tg", &target1) &&
               actual0 <= 1800 && actual1 <= 1800 && target0 <= 1800 && target1 <= 1800;
    }
    if (test != 1 || clock_now() - connection->unlockedAt < 3) return 0;
    if (step == 1) return modes[0] == 3 && modes[1] == 3;
    if (step == 2) return modes[0] == 1 && modes[1] == 3;
    if (modes[0] != 1 || modes[1] != 1) return 0;
    if (step == 4) {
        float target;
        return read_rpm(connection, "F0Tg", &target) && target == 2500;
    }
    return 1;
}

int32_t SMCExperimentOpenPolicyAllows(uint32_t effectiveUID, int32_t profileMatches,
                                      double now, double deadline, int32_t restorationOnly) {
    return effectiveUID == 0 && profileMatches && isfinite(now) && isfinite(deadline) &&
           deadline > now && deadline - now <= (restorationOnly ? 8.0 : 10.0);
}

SMCExperimentConnection *SMCExperimentOpen(double deadline, int32_t restorationOnly) {
    if (!SMCExperimentOpenPolicyAllows(geteuid(), identity_matches(), clock_now(), deadline, restorationOnly)) return NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    if (!matching) return NULL;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, matching);
    if (!service) return NULL;
    SMCExperimentConnection *connection = calloc(1, sizeof(*connection));
    if (!connection) { IOObjectRelease(service); return NULL; }
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &connection->port);
    IOObjectRelease(service);
    if (status != KERN_SUCCESS) { free(connection); return NULL; }
    connection->deadline = deadline;
    connection->restorationOnly = restorationOnly != 0;
    return connection;
}

void SMCExperimentClose(SMCExperimentConnection *connection) {
    if (!connection) return;
    IOServiceClose(connection->port); free(connection);
}

int32_t SMCExperimentWriteStep(SMCExperimentConnection *connection, uint32_t step, SMCExperimentResult *result) {
    if (!connection || !result || step > 9) return -1;
    memset(result, 0, sizeof(*result));
    double now = clock_now();
    if (geteuid() != 0 || !identity_matches() || !isfinite(now) || now >= connection->deadline ||
        (connection->attempted & (1u << step)) ||
        (step < 5 && (connection->restorationOnly || connection->fixedClosed || step != connection->nextFixed))) return -4;
    if (step >= 5) connection->fixedClosed = 1;
    if (!prerequisites(connection, step)) { connection->fixedClosed = 1; return -5; }
    SMCExperimentStep description;
    SMCExperimentDescribeStep(step, &description);
    Packet metadataRequest = {0}, metadataReply = {0};
    metadataRequest.key = code(description.key); metadataRequest.command = 9;
    if (call(connection->port, &metadataRequest, &metadataReply, result) != 0) { connection->fixedClosed = 1; return -6; }
    SMCExperimentRequest request;
    if (SMCExperimentBuildRequest(step, metadataReply.info.type, metadataReply.info.size, &request) != 0) {
        connection->fixedClosed = 1; return -7;
    }
    // Metadata/prerequisite reads may have blocked. Recheck immediately before the write call.
    now = clock_now();
    if (!isfinite(now) || now >= connection->deadline) { connection->fixedClosed = 1; return -4; }
    connection->attempted |= (uint16_t)(1u << step); // Consumed even if IOKit/SMC returns an error.
    Packet reply;
    int status = call(connection->port, (Packet *)&request, &reply, result);
    if (status != 0) connection->fixedClosed = 1;
    else if (step < 5) {
        connection->nextFixed++;
        if (step == 0) connection->unlockedAt = clock_now();
    }
    return status;
}
