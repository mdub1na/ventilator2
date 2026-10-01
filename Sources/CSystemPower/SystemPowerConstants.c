#include "SystemPowerConstants.h"
#include <IOKit/IOMessage.h>

uint32_t VentilatorSystemWillSleepMessage(void) { return kIOMessageSystemWillSleep; }
uint32_t VentilatorCanSystemSleepMessage(void) { return kIOMessageCanSystemSleep; }
