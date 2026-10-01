#ifndef HID_TEMPERATURE_READ_H
#define HID_TEMPERATURE_READ_H
#include <stdint.h>

// Reads only the identified built-in NAND channel; no HID subscriptions or setters.
// Returns 0 for one matching sensor with a finite value and recent event timestamp.
// Missing API/service/event, ambiguous identity or stale event returns a negative code.
int32_t HIDTemperatureReadNAND(double *celsius);
#endif
