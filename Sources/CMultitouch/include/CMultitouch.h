#pragma once
#include <stdbool.h>
#include <stdint.h>

// A trimmed-down touch: what the gesture engine needs, nothing else.
// x and y are normalized 0...1, origin at the bottom-left of the surface.
typedef struct {
    int32_t identifier;
    int32_t state;   // 4 = make touch, 5 = touching, 6+ = lifting
    float x;
    float y;
    float size;
} RTTouch;

// Called on the multitouch thread for every frame of every started device.
// `device` is an opaque key that stays the same for one device until RTStop.
typedef void (*RTFrameHandler)(uintptr_t device, const RTTouch *touches, int32_t count, double timestamp);

// Loads MultitouchSupport and starts every trackpad. Returns the number of devices started
// (0 if the framework could not be loaded or no trackpad is connected).
int32_t RTStart(RTFrameHandler handler);
void RTStop(void);

// Plays a haptic click on the given device's actuator. strength: 1 light, 2 medium, 3 strong.
// Returns false when the device has no usable actuator.
bool RTHaptic(uintptr_t device, int32_t strength);
