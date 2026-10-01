// Read-only SMC capability probe. No write command or arbitrary key input exists here.
// Build: clang -Wall -Wextra -std=c11 tools/smc_read_probe.c -framework IOKit -o /tmp/smc-read-probe
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpu, gpu, memory;
} SMCPLimit;

typedef struct {
    uint32_t size, type;
    uint8_t attributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCPLimit limit;
    SMCKeyInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCKeyData;

_Static_assert(sizeof(SMCKeyData) == 80, "Unexpected SMC request layout");

static uint32_t fourcc(const char key[4]) {
    return ((uint32_t)(uint8_t)key[0] << 24) |
           ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) |
           (uint8_t)key[3];
}

static int call(io_connect_t connection, SMCKeyData *request, SMCKeyData *reply) {
    size_t reply_size = sizeof(*reply);
    memset(reply, 0, sizeof(*reply));
    kern_return_t status = IOConnectCallStructMethod(connection, 2, request,
                                                     sizeof(*request), reply, &reply_size);
    return status == KERN_SUCCESS && reply_size == sizeof(*reply) && reply->result == 0;
}

static void inspect(io_connect_t connection, const char key[4]) {
    SMCKeyData request = {0}, reply = {0};
    request.key = fourcc(key);
    request.command = 9; // Key metadata.
    if (!call(connection, &request, &reply) || reply.info.size > 32) {
        printf("%.4s: unavailable\n", key);
        return;
    }

    uint32_t size = reply.info.size;
    uint32_t type = reply.info.type;
    char type_name[5] = {
        (char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type, 0
    };
    memset(&request, 0, sizeof(request));
    request.key = fourcc(key);
    request.info.size = size;
    request.command = 5; // Read bytes. This program never issues command 6 (write).
    if (!call(connection, &request, &reply)) {
        printf("%.4s (%s, %u bytes): unreadable\n", key, type_name, size);
        return;
    }

    printf("%.4s (%s, %u bytes): ", key, type_name, size);
    if (type == fourcc("flt ") && size == 4) {
        float value;
        memcpy(&value, reply.bytes, sizeof(value));
        if (isfinite(value)) printf("%.1f", value);
        else printf("non-finite");
    } else if (type == fourcc("ui8 ") && size == 1) {
        printf("%u", reply.bytes[0]);
    } else if (type == fourcc("fpe2") && size == 2) {
        printf("%.1f", ((unsigned)reply.bytes[0] * 256 + reply.bytes[1]) / 4.0);
    } else {
        printf("raw");
        for (uint32_t i = 0; i < size; ++i) printf(" %02x", reply.bytes[i]);
    }
    putchar('\n');
}

int main(void) {
    CFMutableDictionaryRef match = IOServiceMatching("AppleSMC");
    if (!match) return 1;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);
    if (!service) {
        fputs("AppleSMC service unavailable\n", stderr);
        return 1;
    }
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (status != KERN_SUCCESS) {
        fprintf(stderr, "AppleSMC open failed: 0x%x\n", status);
        return 1;
    }

    const char *keys[] = {
        "FNum", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F0Md", "F0md",
        "F1Ac", "F1Mn", "F1Mx", "F1Tg", "F1Md", "F1md", "Ftst",
        "Tf26", "TH0F", "TC0P", "TG0P" // Candidates only: no subsystem mapping implied.
    };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i)
        inspect(connection, keys[i]);
    IOServiceClose(connection);
    return 0;
}
