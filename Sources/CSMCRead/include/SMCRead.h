#ifndef SMC_READ_H
#define SMC_READ_H

#include <stdint.h>

// This module exposes reads only. It has no SMC write command.
typedef struct SMCReadConnection SMCReadConnection;

typedef struct {
    uint32_t type;
    uint32_t size;
    uint8_t bytes[32];
} SMCReadValue;

SMCReadConnection *SMCReadOpen(void);
void SMCReadClose(SMCReadConnection *connection);
// Returns 0 for a readable key; negative values for invalid or unavailable keys.
int32_t SMCReadKey(SMCReadConnection *connection, const char *key, SMCReadValue *value);
// Enumerates key names without changing key values. key must hold at least 5 bytes.
int32_t SMCReadKeyNameAtIndex(SMCReadConnection *connection, uint32_t index, char key[5]);

#endif
