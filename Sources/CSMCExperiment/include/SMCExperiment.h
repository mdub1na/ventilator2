#ifndef SMC_EXPERIMENT_H
#define SMC_EXPERIMENT_H
#include <stdint.h>

typedef struct SMCExperimentConnection SMCExperimentConnection;
typedef struct { uint8_t bytes[80]; } SMCExperimentRequest;
typedef struct {
    char key[5];
    uint32_t type, size;
    uint8_t payload[4];
} SMCExperimentStep;
typedef struct { int32_t kernelStatus; uint8_t smcResult, smcStatus; } SMCExperimentResult;

// Ten fixed operations only: 0...4 fixed, 5...9 Auto. Pure functions perform no I/O.
int32_t SMCExperimentDescribeStep(uint32_t step, SMCExperimentStep *description);
int32_t SMCExperimentBuildRequest(uint32_t step, uint32_t actualType, uint32_t actualSize,
                                  SMCExperimentRequest *request);
int32_t SMCExperimentValidateReply(int32_t kernelStatus, uint32_t size, const SMCExperimentRequest *reply,
                                   SMCExperimentResult *result);
int32_t SMCExperimentOpenPolicyAllows(uint32_t effectiveUID, int32_t profileMatches,
                                      double now, double deadline, int32_t restorationOnly);

// Root, exact hardware/build, finite future deadline; each operation is attempted at most once.
// No generic key/byte writer exists. Opening a connection is not itself owner authorization.
SMCExperimentConnection *SMCExperimentOpen(double deadline, int32_t restorationOnly);
void SMCExperimentClose(SMCExperimentConnection *connection);
int32_t SMCExperimentWriteStep(SMCExperimentConnection *connection, uint32_t step, SMCExperimentResult *result);
#endif
