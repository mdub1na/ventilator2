#include "SMCRead.h"

#include <IOKit/IOKitLib.h>
#include <stdlib.h>
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

struct SMCReadConnection {
    io_connect_t port;
};

static uint32_t key_code(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) |
           ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) |
           (uint8_t)key[3];
}

static int call_smc(io_connect_t port, SMCKeyData *request, SMCKeyData *reply) {
    size_t reply_size = sizeof(*reply);
    memset(reply, 0, sizeof(*reply));
    kern_return_t status = IOConnectCallStructMethod(port, 2, request,
                                                     sizeof(*request), reply, &reply_size);
    return status == KERN_SUCCESS && reply_size == sizeof(*reply) && reply->result == 0;
}

SMCReadConnection *SMCReadOpen(void) {
    CFMutableDictionaryRef match = IOServiceMatching("AppleSMC");
    if (!match) return NULL;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);
    if (!service) return NULL;
    SMCReadConnection *connection = calloc(1, sizeof(*connection));
    if (!connection) {
        IOObjectRelease(service);
        return NULL;
    }
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &connection->port);
    IOObjectRelease(service);
    if (status != KERN_SUCCESS) {
        free(connection);
        return NULL;
    }
    return connection;
}

void SMCReadClose(SMCReadConnection *connection) {
    if (!connection) return;
    IOServiceClose(connection->port);
    free(connection);
}

int32_t SMCReadKey(SMCReadConnection *connection, const char *key, SMCReadValue *value) {
    if (!connection || !key || !value || strlen(key) != 4) return -1;
    SMCKeyData request = {0}, reply = {0};
    request.key = key_code(key);
    request.command = 9; // Read key metadata.
    if (!call_smc(connection->port, &request, &reply)) return -2;
    if (reply.info.size == 0 || reply.info.size > sizeof(value->bytes)) return -3;

    uint32_t size = reply.info.size;
    uint32_t type = reply.info.type;
    memset(&request, 0, sizeof(request));
    request.key = key_code(key);
    request.info.size = size;
    request.command = 5; // Read bytes. Command 6 (write) is deliberately absent.
    if (!call_smc(connection->port, &request, &reply)) return -4;
    value->size = size;
    value->type = type;
    memcpy(value->bytes, reply.bytes, size);
    return 0;
}

int32_t SMCReadKeyNameAtIndex(SMCReadConnection *connection, uint32_t index, char key[5]) {
    if (!connection || !key || index >= 10000) return -1;
    SMCKeyData request = {0}, reply = {0};
    request.command = 8; // Read the key name at an index.
    request.index = index;
    if (!call_smc(connection->port, &request, &reply)) return -2;
    key[0] = (char)(reply.key >> 24);
    key[1] = (char)(reply.key >> 16);
    key[2] = (char)(reply.key >> 8);
    key[3] = (char)reply.key;
    key[4] = 0;
    return 0;
}
