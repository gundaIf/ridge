// Bridge to the private MultitouchSupport framework. It is loaded with dlopen because private
// frameworks ship only in the dyld shared cache, so there is nothing to link against.
#include "CMultitouch.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier, state, fingerID, handID;
    MTVector normalized;
    float size;
    int32_t zero1;
    float angle, majorAxis, minorAxis;
    MTVector absolute;
    int32_t zero2, zero3;
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef, MTTouch *, int, double, int);

static CFMutableArrayRef (*pCreateList)(void);
static void (*pRegister)(MTDeviceRef, MTContactCallback);
static void (*pUnregister)(MTDeviceRef, MTContactCallback);
static void (*pStart)(MTDeviceRef, int);
static void (*pStop)(MTDeviceRef);
static int32_t (*pGetFamilyID)(MTDeviceRef, int32_t *);
static int32_t (*pGetDeviceID)(MTDeviceRef, uint64_t *);
static CFTypeRef (*pActuatorCreate)(uint64_t);
static int32_t (*pActuatorOpen)(CFTypeRef);
static int32_t (*pActuatorActuate)(CFTypeRef, int32_t, uint32_t, float, float);

#define MAX_DEVICES 8
static MTDeviceRef devices[MAX_DEVICES];
static CFTypeRef actuators[MAX_DEVICES];
static int32_t deviceCount;
static RTFrameHandler frameHandler;

static bool load(void) {
    static bool loaded, ok;
    if (loaded) return ok;
    loaded = true;
    void *h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
    if (!h) return false;
    pCreateList = dlsym(h, "MTDeviceCreateList");
    pRegister = dlsym(h, "MTRegisterContactFrameCallback");
    pUnregister = dlsym(h, "MTUnregisterContactFrameCallback");
    pStart = dlsym(h, "MTDeviceStart");
    pStop = dlsym(h, "MTDeviceStop");
    pGetFamilyID = dlsym(h, "MTDeviceGetFamilyID");
    pGetDeviceID = dlsym(h, "MTDeviceGetDeviceID");
    pActuatorCreate = dlsym(h, "MTActuatorCreateFromDeviceID");
    pActuatorOpen = dlsym(h, "MTActuatorOpen");
    pActuatorActuate = dlsym(h, "MTActuatorActuate");
    ok = pCreateList && pRegister && pStart && pStop;
    return ok;
}

static int contactCallback(MTDeviceRef device, MTTouch *data, int count, double timestamp, int frame) {
    (void)frame;
    RTFrameHandler handler = frameHandler;
    if (!handler) return 0;
    RTTouch touches[16];
    int n = count < 16 ? count : 16;
    for (int i = 0; i < n; i++) {
        touches[i].identifier = data[i].identifier;
        touches[i].state = data[i].state;
        touches[i].x = data[i].normalized.position.x;
        touches[i].y = data[i].normalized.position.y;
        touches[i].size = data[i].size;
    }
    handler((uintptr_t)device, touches, n, timestamp);
    return 0;
}

int32_t RTStart(RTFrameHandler handler) {
    if (!load()) return 0;
    RTStop();
    frameHandler = handler;
    // The list is intentionally never released: releasing it after MTDeviceStop has been
    // seen to crash, and it is only recreated on wake or when a trackpad reconnects.
    CFMutableArrayRef list = pCreateList();
    if (!list) return 0;
    CFIndex total = CFArrayGetCount(list);
    for (CFIndex i = 0; i < total && deviceCount < MAX_DEVICES; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
        int32_t family = 0;
        if (pGetFamilyID) pGetFamilyID(device, &family);
        if (family == 112 || family == 113) continue; // Magic Mouse
        CFTypeRef actuator = NULL;
        uint64_t deviceID = 0;
        if (pGetDeviceID && pActuatorCreate && pActuatorOpen && pGetDeviceID(device, &deviceID) == 0) {
            actuator = pActuatorCreate(deviceID);
            if (actuator && pActuatorOpen(actuator) != 0) { CFRelease(actuator); actuator = NULL; }
        }
        pRegister(device, contactCallback);
        pStart(device, 0);
        devices[deviceCount] = device;
        actuators[deviceCount] = actuator;
        deviceCount++;
    }
    return deviceCount;
}

void RTStop(void) {
    for (int32_t i = 0; i < deviceCount; i++) {
        if (pUnregister) pUnregister(devices[i], contactCallback);
        pStop(devices[i]);
        if (actuators[i]) CFRelease(actuators[i]);
        devices[i] = NULL;
        actuators[i] = NULL;
    }
    deviceCount = 0;
}

bool RTHaptic(uintptr_t device, int32_t strength) {
    if (!pActuatorActuate) return false;
    // Actuation patterns built into the Force Touch trackpad, weakest to strongest.
    static const int32_t patterns[] = {0, 3, 4, 6};
    if (strength < 1) return true;
    if (strength > 3) strength = 3;
    for (int32_t i = 0; i < deviceCount; i++) {
        if ((uintptr_t)devices[i] != device) continue;
        if (!actuators[i]) return false;
        return pActuatorActuate(actuators[i], patterns[strength], 0, 0.0f, 2.0f) == 0;
    }
    return false;
}
