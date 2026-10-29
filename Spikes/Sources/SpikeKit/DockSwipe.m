// Synthetic DockSwipe events.
// Ported from jurplel/InstantSpaceSwitcher (MIT, Copyright (c) 2026 jurplel):
// Sources/ISS/ISS.c iss_post_modern_dock_swipe and Sources/ISS/event_serialize.c.
// Change from upstream: progress and velocity are parameters (upstream posts a near-zero
// progress and a 9999 fling to skip the animation; the spike wants the animated slide).
#import "Spike.h"
#import <mach/mach_time.h>

#pragma pack(push, 1)
typedef struct { uint32_t size, type, options; uint8_t depth, reserved[3]; } HIDBase;
typedef struct { HIDBase base; int32_t px, py, pz; uint32_t swipeMask; uint16_t motion, flavor; int32_t progress; } HIDFluid;
typedef struct { HIDBase base; int32_t vx, vy, vz; } HIDVelocity;
typedef struct { uint64_t timestamp, sender; uint32_t options, attrLen, count; } HIDQueueHeader;
#pragma pack(pop)
_Static_assert(sizeof(HIDFluid) == 40, "layout");
_Static_assert(sizeof(HIDVelocity) == 28, "layout");
_Static_assert(sizeof(HIDQueueHeader) == 28, "layout");

static int32_t Fixed1616(double v) {
  int32_t f = (int32_t)(v * 65536.0);
  return (f == 0 && v != 0.0) ? (v > 0 ? 1 : -1) : f;
}

// macOS 27: the Dock reads the IOHID fluid-gesture payload appended to the serialized event
// under tag 4205; without it the posted DockControl event is ignored.
static CGEventRef Augment(CGEventRef ev) {
  NSData *data = CFBridgingRelease(CGEventCreateData(kCFAllocatorDefault, ev));
  const uint8_t *b = data.bytes;
  if (data.length < 4 || b[0] || b[1] || b[2] || b[3] != 2) return NULL;  // serialization v2 only
  int64_t phase = CGEventGetIntegerValueField(ev, 132), motion = CGEventGetIntegerValueField(ev, 123);
  double progress = CGEventGetDoubleValueField(ev, 124), px = CGEventGetDoubleValueField(ev, 125),
         py = CGEventGetDoubleValueField(ev, 126), vx = CGEventGetDoubleValueField(ev, 129),
         vy = CGEventGetDoubleValueField(ev, 130);
  bool vel = vx != 0 || vy != 0 || phase == 4;
  size_t len = sizeof(HIDQueueHeader) + sizeof(HIDFluid) + (vel ? sizeof(HIDVelocity) : 0);
  NSMutableData *payload = [NSMutableData dataWithLength:len];
  HIDQueueHeader *h = payload.mutableBytes;
  h->timestamp = CGEventGetTimestamp(ev) ?: mach_absolute_time();
  h->count = vel ? 2 : 1;
  HIDFluid *f = (HIDFluid *)(h + 1);
  f->base.size = sizeof(HIDFluid); f->base.type = 23; f->base.options = (uint32_t)((phase & 0xFF) << 24);
  f->px = Fixed1616(px); f->py = Fixed1616(py);
  f->swipeMask = (uint32_t)CGEventGetIntegerValueField(ev, 115);
  f->motion = (uint16_t)motion; f->flavor = 3; f->progress = Fixed1616(progress);
  if (vel) {
    HIDVelocity *v = (HIDVelocity *)(f + 1);
    v->base.size = sizeof(HIDVelocity); v->base.type = 9; v->base.depth = 1;
    v->vx = Fixed1616(vx); v->vy = Fixed1616(vy);
  }
  NSMutableData *out = [data mutableCopy];
  uint8_t tag[4] = {(uint8_t)(len >> 8), (uint8_t)len, (uint8_t)(4205 >> 8), (uint8_t)(4205 & 0xFF)};
  [out appendBytes:tag length:4];
  [out appendData:payload];
  return CGEventCreateFromData(kCFAllocatorDefault, (__bridge CFDataRef)out);
}

double SpikeSwipeSign(int direction) {
  Boolean valid = false;
  Boolean natural = CFPreferencesGetAppBooleanValue(CFSTR("com.apple.swipescrolldirection"), kCFPreferencesAnyApplication, &valid);
  double sign = direction > 0 ? -1.0 : 1.0;  // on 27 "next Space" is negative with natural scrolling
  return (!valid || natural) ? sign : -sign;
}

bool SpikePostDockSwipe(int phase, double progress, double velocity, bool modern) {
  CGEventRef ev = CGEventCreate(NULL);
  if (!ev) return false;
  CGEventSetIntegerValueField(ev, 55, 30);   // kCGSEventDockControl
  CGEventSetIntegerValueField(ev, 110, 23);  // kIOHIDEventTypeDockSwipe
  CGEventSetIntegerValueField(ev, 132, phase);
  CGEventSetIntegerValueField(ev, 123, 1);   // horizontal
  CGEventSetDoubleValueField(ev, 124, progress);
  if (!modern) {
    CGEventSetDoubleValueField(ev, 129, velocity);
    CGEventSetDoubleValueField(ev, 130, velocity);
    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
    return true;
  }
  CGEventSetIntegerValueField(ev, 134, phase);
  CGEventSetDoubleValueField(ev, 138, 3.0);
  CGEventSetDoubleValueField(ev, 169, (double)mach_absolute_time());
  CGEventSetDoubleValueField(ev, 125, 0.1);
  if (phase == 4) CGEventSetDoubleValueField(ev, 129, velocity);
  CGEventRef aug = Augment(ev);
  CFRelease(ev);
  if (!aug) return false;
  CGEventRef companion = CGEventCreate(NULL);  // the Dock ignores DockControl without a Gesture companion
  CGEventSetIntegerValueField(companion, 55, 29);
  CGEventPost(kCGSessionEventTap, aug);
  CGEventPost(kCGSessionEventTap, companion);
  CFRelease(aug);
  CFRelease(companion);
  return true;
}
