// S1 bridged move, S2 animated DockSwipe, S6 system spring recordings, S12 off-Space thumbnails.
#import "Spike.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

static void Pump(double s) { SpikePump(s); }
static uint64_t Active(void) { return SLS.GetActiveSpace ? SLS.GetActiveSpace(gCID) : 0; }

// User Desktops (type 0) of the first display, in Mission Control order.
static NSArray<NSNumber *> *Desktops(void) {
  NSMutableArray *out = [NSMutableArray array];
  NSString *firstDisplay = nil;
  for (NSDictionary *s in SpikeUserSpaces()) {
    if (!firstDisplay) firstDisplay = s[@"display"];
    if ([s[@"display"] isEqual:firstDisplay] && [s[@"type"] intValue] == 0) [out addObject:s[@"id"]];
  }
  return out;
}

static BOOL WaitFor(BOOL (^cond)(void), double timeout) {
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (!cond()) {
    if ([limit timeIntervalSinceNow] <= 0) return NO;
    Pump(0.01);
  }
  return YES;
}

static NSString *BridgedMove(NSArray<NSNumber *> *wids, uint64_t sid) {
  Class cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation");
  SEL sel = sel_registerName("initWithWindows:spaceID:");
  if (!cls) return @"class missing";
  if (![cls instancesRespondToSelector:sel]) return @"initWithWindows:spaceID: missing";
  if (!SLS.PerformAsyncBridgedOp) return @"perform function missing";
  id op = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)([cls alloc], sel, wids, sid);
  SLS.PerformAsyncBridgedOp(op);
  return @"posted";
}

static BOOL OnScreen(uint32_t wid) {
  NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
  for (NSDictionary *w in list) if ([w[(id)kCGWindowNumber] unsignedIntValue] == wid) return YES;
  return NO;
}

typedef void (^Mover)(NSArray *wids, uint64_t sid);

static NSDictionary *MoveRoundTrip(NSString *label, uint32_t wid, uint64_t home, uint64_t target, Mover move) {
  NSArray *before = SpikeSpacesForWindow(wid);
  double t0 = CACurrentMediaTime();
  move(@[@(wid)], target);
  BOOL moved = WaitFor(^{ return [SpikeSpacesForWindow(wid) containsObject:@(target)]; }, 2.0);
  double latency = CACurrentMediaTime() - t0;
  NSArray *after = SpikeSpacesForWindow(wid);
  BOOL visibleAfter = OnScreen(wid);
  uint64_t activeAfter = Active();
  move(@[@(wid)], home);
  BOOL back = WaitFor(^{ return [SpikeSpacesForWindow(wid) containsObject:@(home)]; }, 2.0);
  return @{@"target": label, @"wid": @(wid), @"spacesBefore": before, @"spacesAfter": after, @"moved": @(moved),
           @"latencyS": @(moved ? latency : -1), @"onScreenAfterMove": @(visibleAfter),
           @"activeSpaceUnchanged": @(activeAfter == home), @"restored": @(back), @"spacesRestored": SpikeSpacesForWindow(wid)};
}

void TestS1(NSDictionary *a, SpikeDone done) {
  NSArray *desk = Desktops();
  uint64_t home = Active();
  Class cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation");
  NSMutableDictionary *r = [@{@"test": @"S1", @"desktops": desk, @"activeSpace": @(home),
    @"classFound": @(cls != nil), @"initSelector": @(cls && [cls instancesRespondToSelector:sel_registerName("initWithWindows:spaceID:")]),
    @"performResolved": @(SLS.PerformAsyncBridgedOp != NULL),
    @"classMethods": ({ NSMutableArray *m = [NSMutableArray array]; unsigned n = 0;
                        Method *ms = cls ? class_copyMethodList(cls, &n) : NULL;
                        for (unsigned i = 0; i < n; i++) [m addObject:NSStringFromSelector(method_getName(ms[i]))];
                        free(ms); m; })} mutableCopy];
  NSWindow *w = SpikeMakeWindow(NSMakeRect(160, 160, 360, 240), NSColor.systemGrayColor, @"FDS S1 scratch", YES);
  Pump(0.4);
  uint32_t wid = SpikeWID(w);
  Mover bridged = ^(NSArray *wids, uint64_t sid) { (void)BridgedMove(wids, sid); };
  Mover direct = ^(NSArray *wids, uint64_t sid) { if (SLS.MoveWindowsToManagedSpace) SLS.MoveWindowsToManagedSpace(gCID, (__bridge CFArrayRef)wids, sid); };
  if (desk.count < 2) {
    r[@"noopCall"] = BridgedMove(@[@(wid)], home);
    Pump(0.6);
    r[@"spacesAfterNoop"] = SpikeSpacesForWindow(wid);
    [w close];
    NSMutableDictionary *b = [SpikeBlocked(@"S1", @"only one Desktop exists; a move needs a second user Space", @[@"2+ Desktops in Mission Control"]) mutableCopy];
    [b addEntriesFromDictionary:r];
    done(b);
    return;
  }
  uint64_t target = 0;
  for (NSNumber *s in desk) if (s.unsignedLongLongValue != home) { target = s.unsignedLongLongValue; break; }
  r[@"targetSpace"] = @(target);
  NSMutableArray *rows = [NSMutableArray array];
  [rows addObject:MoveRoundTrip(@"own window, bridged op", wid, home, target, bridged)];
  [rows addObject:MoveRoundTrip(@"own window, SLSMoveWindowsToManagedSpace", wid, home, target, direct)];
  [w close];
  pid_t te = SpikeOpenScratchTextEdit(@"s1-scratch.txt", @"FocusDock spike S1 scratch document.\n", 15);
  uint32_t twid = 0;
  for (NSDictionary *x in SpikeWindowsOfPID(te))
    if ([x[(id)kCGWindowLayer] intValue] == 0 && [x[(id)kCGWindowBounds][@"Height"] doubleValue] > 100) { twid = [x[(id)kCGWindowNumber] unsignedIntValue]; break; }
  if (twid) {
    [rows addObject:MoveRoundTrip(@"TextEdit scratch window, bridged op", twid, home, target, bridged)];
    [rows addObject:MoveRoundTrip(@"TextEdit scratch window, SLSMoveWindowsToManagedSpace", twid, home, target, direct)];
  }
  SpikeQuitApp(te);
  r[@"rows"] = rows;
  r[@"activeSpaceAtEnd"] = @(Active());
  BOOL ownOK = [rows[0][@"moved"] boolValue] && [rows[0][@"restored"] boolValue];
  BOOL foreignOK = rows.count > 2 && [rows[2][@"moved"] boolValue] && [rows[2][@"restored"] boolValue];
  r[@"status"] = (ownOK && foreignOK) ? @"PASS" : (ownOK || foreignOK) ? @"PARTIAL" : @"FAIL";
  done(r);
}

// ---- event posting helpers (need Accessibility) ----
static void PostSwipe(int dir, int steps, double step, double velocity, double interval) {
  double sign = SpikeSwipeSign(dir);
  SpikePostDockSwipe(1, 0, 0, true);
  for (int k = 1; k <= steps; k++) {
    usleep((useconds_t)(interval * 1e6));
    SpikePostDockSwipe(2, sign * step * k, 0, true);
  }
  usleep((useconds_t)(interval * 1e6));
  SpikePostDockSwipe(4, sign * step * steps, sign * velocity, true);
}

static void PostKey(CGKeyCode key, CGEventFlags flags) {
  CGEventRef d = CGEventCreateKeyboardEvent(NULL, key, true), u = CGEventCreateKeyboardEvent(NULL, key, false);
  CGEventSetFlags(d, flags); CGEventSetFlags(u, flags);
  CGEventPost(kCGHIDEventTap, d); CGEventPost(kCGHIDEventTap, u);
  CFRelease(d); CFRelease(u);
}

// Ctrl+Arrow as the keyboard sends it (Fn and NumPad flags set on arrow keys; hotkeys 79/81 expect 0x840000).
static void PostCtrlArrow(int dir) {
  PostKey(dir > 0 ? 124 : 123, kCGEventFlagMaskControl | kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskNumericPad);
}

static BOOL ReturnHome(uint64_t home, NSArray *desk) {
  for (int tries = 0; tries < 6 && Active() != home; tries++) {
    NSUInteger cur = [desk indexOfObject:@(Active())], want = [desk indexOfObject:@(home)];
    if (cur == NSNotFound || want == NSNotFound) break;
    PostSwipe(want > cur ? 1 : -1, 1, 0.000016, 9999, 0.008);
    WaitFor(^{ return (BOOL)(Active() != ((NSNumber *)desk[cur]).unsignedLongLongValue); }, 1.5);
    Pump(0.4);
  }
  return Active() == home;
}

static void WriteSamples(NSArray *samples, NSDictionary *meta, NSString *name) {
  NSDictionary *doc = @{@"meta": meta, @"samples": samples};
  NSData *d = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
  [d writeToFile:[gEvidenceDir stringByAppendingPathComponent:name] atomically:YES];
}

static NSArray *Needs(BOOL ax, BOOL sr, NSUInteger desktops, NSUInteger minDesktops) {
  NSMutableArray *n = [NSMutableArray array];
  if (ax && !AXIsProcessTrusted()) [n addObject:@"Accessibility"];
  if (sr && !CGPreflightScreenCaptureAccess()) [n addObject:@"Screen Recording"];
  if (desktops < minDesktops) [n addObject:[NSString stringWithFormat:@"%lu+ Desktops in Mission Control", (unsigned long)minDesktops]];
  return n;
}

static NSWindow *MakeMarker(BOOL titled) {
  NSRect s = NSScreen.mainScreen.frame;
  NSWindow *m = SpikeMakeWindow(NSMakeRect(NSMidX(s) - 120, NSMidY(s) - 120, 240, 240),
                                [NSColor colorWithSRGBRed:1 green:0 blue:1 alpha:1], @"FDS marker", titled);
  m.ignoresMouseEvents = YES;
  return m;
}

// Records one action; `act` returns after it has posted its events, `settle` keeps recording.
static int gSaveEvery;  // debug: save every Nth recorded frame as PNG (arg saveEvery=N)

static void Record(NSString *name, NSDictionary *meta, double settle, void (^act)(NSMutableDictionary *marks), void (^then)(NSDictionary *summary)) {
  SpikeRecorder *rec = [SpikeRecorder new];
  if (gSaveEvery > 0) { rec.saveFramesPrefix = [gEvidenceDir stringByAppendingPathComponent:name]; rec.saveEvery = gSaveEvery; }
  [rec startOnMainDisplayFPS:120 completion:^(NSError *err) {
    if (err) { then(@{@"name": name, @"error": err.description}); return; }
    Pump(0.35);
    NSMutableDictionary *marks = [NSMutableDictionary dictionaryWithDictionary:@{@"tStart": @(CACurrentMediaTime())}];
    act(marks);
    Pump(settle);
    [rec stop:^{
      NSMutableDictionary *m = [meta mutableCopy];
      [m addEntriesFromDictionary:marks];
      m[@"frames"] = @(rec.framesSeen);
      WriteSamples(rec.samples, m, [name stringByAppendingString:@".json"]);
      then(@{@"name": name, @"frames": @(rec.framesSeen), @"marks": marks});
    }];
  }];
}

// Runs blocks one after another; each calls next() when finished.
static void Chain(NSArray *steps, dispatch_block_t finish) {
  if (!steps.count) { finish(); return; }
  void (^step)(dispatch_block_t) = steps.firstObject;
  NSArray *rest = [steps subarrayWithRange:NSMakeRange(1, steps.count - 1)];
  step(^{ SpikeOnMain(^{ Chain(rest, finish); }); });
}

void TestS2(NSDictionary *a, SpikeDone done) {
  NSArray *desk = Desktops();
  NSArray *needs = Needs(YES, YES, desk.count, 2);
  if (needs.count) { done(SpikeBlocked(@"S2", @"prerequisites missing", needs)); return; }
  uint64_t home = Active();
  NSUInteger hi = [desk indexOfObject:@(home)];
  int dir = (hi + 1 < desk.count) ? 1 : -1;
  gSaveEvery = [a[@"saveEvery"] intValue];
  NSWindow *m = MakeMarker(YES);  // a borderless marker never reached the screen on 27 (run F)
  SpikeAddCleanup(^{ [m close]; ReturnHome(home, desk); });
  Pump(0.5);
  NSArray *vels = [(a[@"velocities"] ?: @"0.25,1,4,16,9999") componentsSeparatedByString:@","];
  double step = a[@"step"] ? [a[@"step"] doubleValue] : 0.03;
  int steps = a[@"steps"] ? [a[@"steps"] intValue] : 10;
  NSMutableArray *runs = [NSMutableArray array];
  NSMutableArray *plan = [NSMutableArray array];
  // Legacy (pre-27, no IOHID payload) format once, to show whether 27 still accepts it.
  [plan addObject:^(dispatch_block_t next) {
    double sign = SpikeSwipeSign(dir);
    SpikePostDockSwipe(1, sign, sign * 9999, false);
    SpikePostDockSwipe(4, sign, sign * 9999, false);
    BOOL moved = WaitFor(^{ return (BOOL)(Active() != home); }, 1.5);
    [runs addObject:@{@"run": @"legacy-format", @"switched": @(moved)}];
    Pump(0.5);
    ReturnHome(home, desk);
    Pump(0.5);
    next();
  }];
  for (NSString *vs in vels) {
    double v = vs.doubleValue;
    [plan addObject:^(dispatch_block_t next) {
      NSString *name = [NSString stringWithFormat:@"s2-v%@", vs];
      Record(name, @{@"velocity": @(v), @"step": @(step), @"steps": @(steps), @"dir": @(dir)}, 0.1, ^(NSMutableDictionary *marks) {
        marks[@"tOutEvents"] = @(CACurrentMediaTime());
        PostSwipe(dir, steps, step, v, 1.0 / 120);
        marks[@"tOutEnded"] = @(CACurrentMediaTime());
        BOOL out = WaitFor(^{ return (BOOL)(Active() != home); }, 2.0);
        marks[@"switchedOut"] = @(out);
        marks[@"tOutActiveChanged"] = @(CACurrentMediaTime());
        Pump(1.2);
        marks[@"tBackEvents"] = @(CACurrentMediaTime());
        if (out) PostSwipe(-dir, steps, step, v, 1.0 / 120);
        marks[@"tBackEnded"] = @(CACurrentMediaTime());
        BOOL back = out && WaitFor(^{ return (BOOL)(Active() == home); }, 2.0);
        marks[@"switchedBack"] = @(back);
        marks[@"tBackActiveChanged"] = @(CACurrentMediaTime());
        Pump(1.4);
      }, ^(NSDictionary *summary) {
        [runs addObject:summary];
        ReturnHome(home, desk);
        Pump(0.4);
        next();
      });
    }];
  }
  // Chained k-Space jump with fast gestures.
  if (desk.count >= 3) {
    NSUInteger k = MIN(3, dir > 0 ? desk.count - 1 - hi : hi);
    double cv = a[@"chainVelocity"] ? [a[@"chainVelocity"] doubleValue] : 4;
    for (NSNumber *gap in @[@0.0, @0.25]) {
      [plan addObject:^(dispatch_block_t next) {
        NSString *name = [NSString stringWithFormat:@"s2-chain%lu-gap%.2f", (unsigned long)k, gap.doubleValue];
        uint64_t want = [desk[(NSUInteger)((long)hi + dir * (long)k)] unsignedLongLongValue];
        Record(name, @{@"k": @(k), @"velocity": @(cv), @"gap": gap}, 0.1, ^(NSMutableDictionary *marks) {
          marks[@"tEvents"] = @(CACurrentMediaTime());
          for (NSUInteger i = 0; i < k; i++) { PostSwipe(dir, steps, step, cv, 1.0 / 120); if (gap.doubleValue > 0) Pump(gap.doubleValue); }
          BOOL ok = WaitFor(^{ return (BOOL)(Active() == want); }, 4.0);
          marks[@"reachedTarget"] = @(ok);
          marks[@"tReached"] = @(CACurrentMediaTime());
          marks[@"landedOn"] = @([desk indexOfObject:@(Active())] + 1);
          Pump(1.0);
        }, ^(NSDictionary *summary) {
          [runs addObject:summary];
          ReturnHome(home, desk);
          Pump(0.5);
          next();
        });
      }];
    }
  }
  Chain(plan, ^{
    [m close];
    BOOL home_ = ReturnHome(home, desk);
    done(@{@"test": @"S2", @"status": @"MEASURED", @"runs": runs, @"returnedHome": @(home_), @"evidenceDir": gEvidenceDir});
  });
}

// ---- S6: system springs ----
static NSDictionary *(^DockColumnAnalyzer(long x, long yTop, long yBottom))(const uint8_t *, size_t, size_t, size_t, double) {
  __block NSMutableData *baseline = nil;
  return ^NSDictionary *(const uint8_t *base, size_t w, size_t h, size_t row, double t) {
    long y0 = MAX(0, yTop), y1 = MIN((long)h - 1, yBottom);
    if (x < 0 || x >= (long)w || y1 <= y0) return nil;
    if (!baseline) {
      baseline = [NSMutableData dataWithLength:(NSUInteger)(y1 - y0 + 1) * 4];
      uint8_t *b = baseline.mutableBytes;
      for (long y = y0; y <= y1; y++) memcpy(b + (y - y0) * 4, base + y * row + x * 4, 4);
      return @{@"t": @(t), @"top": @(-1), @"baseline": @YES};
    }
    const uint8_t *b = baseline.bytes;
    long top = -1;
    for (long y = y0; y <= y1; y++) {
      const uint8_t *p = base + y * row + x * 4, *q = b + (y - y0) * 4;
      if (abs(p[0] - q[0]) + abs(p[1] - q[1]) + abs(p[2] - q[2]) > 60) { top = y; break; }
    }
    return @{@"t": @(t), @"top": @(top)};
  };
}

static void PostMouseMove(CGPoint p) {
  CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, e);
  CFRelease(e);
}

void TestS6(NSDictionary *a, SpikeDone done) {
  NSArray *desk = Desktops();
  if (!CGPreflightScreenCaptureAccess()) { done(SpikeBlocked(@"S6", @"recording needs Screen Recording", @[@"Screen Recording"])); return; }
  uint64_t home = Active();
  NSUInteger hi = [desk indexOfObject:@(home)];
  int dir = (hi + 1 < desk.count) ? 1 : -1;
  NSMutableArray *parts = [NSMutableArray array];
  NSMutableArray *plan = [NSMutableArray array];
  NSString *only = a[@"only"];  // slide | mc | mag
  NSWindow *m = MakeMarker(YES);
  SpikeAddCleanup(^{ [m close]; if (AXIsProcessTrusted()) ReturnHome(home, desk); });
  Pump(0.5);
  BOOL slideOK = AXIsProcessTrusted() && desk.count >= 2 && SLS.IsSymbolicHotKeyEnabled && SLS.IsSymbolicHotKeyEnabled(79) && SLS.IsSymbolicHotKeyEnabled(81);
  if (!only || [only isEqual:@"slide"]) {
    if (!slideOK) [parts addObject:@{@"part": @"slide", @"status": @"BLOCKED", @"needs": Needs(YES, YES, desk.count, 2), @"hotkeys79_81": @(SLS.IsSymbolicHotKeyEnabled && SLS.IsSymbolicHotKeyEnabled(79))}];
    else [plan addObject:^(dispatch_block_t next) {
      Record(@"s6-slide-ctrl-arrow", @{@"dir": @(dir)}, 0.1, ^(NSMutableDictionary *marks) {
        marks[@"tOut"] = @(CACurrentMediaTime());
        PostCtrlArrow(dir);
        marks[@"switchedOut"] = @(WaitFor(^{ return (BOOL)(Active() != home); }, 2.0));
        Pump(1.2);
        marks[@"tBack"] = @(CACurrentMediaTime());
        PostCtrlArrow(-dir);
        marks[@"switchedBack"] = @(WaitFor(^{ return (BOOL)(Active() == home); }, 2.0));
        Pump(1.4);
      }, ^(NSDictionary *s) { [parts addObject:s]; ReturnHome(home, desk); Pump(0.4); next(); });
    }];
  }
  if (!only || [only isEqual:@"mc"]) {
    [plan addObject:^(dispatch_block_t next) {
      if (!SLS.CoreDockSendNotification) { [parts addObject:@{@"part": @"mc", @"status": @"FAIL", @"why": @"CoreDockSendNotification missing"}]; next(); return; }
      Record(@"s6-mission-control", @{}, 0.1, ^(NSMutableDictionary *marks) {
        marks[@"tEnter"] = @(CACurrentMediaTime());
        SLS.CoreDockSendNotification(CFSTR("com.apple.expose.awake"), 0);
        Pump(1.6);
        marks[@"tExit"] = @(CACurrentMediaTime());
        SLS.CoreDockSendNotification(CFSTR("com.apple.expose.awake"), 0);
        Pump(1.6);
      }, ^(NSDictionary *s) { [parts addObject:s]; next(); });
    }];
  }
  NSNumber *mag = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("magnification"), CFSTR("com.apple.dock")));
  if (!only || [only isEqual:@"mag"]) {
    if (!mag.boolValue) [parts addObject:@{@"part": @"mag", @"status": @"BLOCKED-USER-SETTING", @"why": @"Dock magnification is off"}];
    else if (!AXIsProcessTrusted()) [parts addObject:@{@"part": @"mag", @"status": @"BLOCKED", @"needs": @[@"Accessibility"]}];
    else [plan addObject:^(dispatch_block_t next) {
      [m orderOut:nil];
      NSScreen *s = NSScreen.mainScreen;
      double H = s.frame.size.height, dockH = s.visibleFrame.origin.y;  // bottom Dock height in points
      double x = a[@"magX"] ? [a[@"magX"] doubleValue] : NSMidX(s.frame);
      CGEventRef cur = CGEventCreate(NULL); CGPoint saved = CGEventGetLocation(cur); CFRelease(cur);
      SpikeAddCleanup(^{ CGWarpMouseCursorPosition(saved); });
      PostMouseMove(CGPointMake(x, H - dockH - 260));
      Pump(0.6);
      SpikeRecorder *rec = [SpikeRecorder new];
      if ([a[@"saveEvery"] intValue] > 0) { rec.saveFramesPrefix = [gEvidenceDir stringByAppendingPathComponent:@"s6-magnification"]; rec.saveEvery = [a[@"saveEvery"] intValue]; }
      rec.analyzer = DockColumnAnalyzer((long)x, (long)(H - dockH - 140), (long)H - 1);
      [rec startOnMainDisplayFPS:120 completion:^(NSError *err) {
        Pump(0.4);
        NSMutableDictionary *marks = [NSMutableDictionary dictionary];
        marks[@"tIn"] = @(CACurrentMediaTime());
        PostMouseMove(CGPointMake(x, H - dockH / 2));
        Pump(1.2);
        marks[@"tOut"] = @(CACurrentMediaTime());
        PostMouseMove(CGPointMake(x, H - dockH - 260));
        Pump(1.2);
        [rec stop:^{
          CGWarpMouseCursorPosition(saved);
          WriteSamples(rec.samples, @{@"x": @(x), @"dockH": @(dockH), @"H": @(H), @"tIn": marks[@"tIn"], @"tOut": marks[@"tOut"],
                                      @"error": err.description ?: @""}, @"s6-magnification.json");
          [parts addObject:@{@"name": @"s6-magnification", @"frames": @(rec.framesSeen), @"error": err.description ?: @""}];
          next();
        }];
      }];
    }];
  }
  Chain(plan, ^{
    [m close];
    done(@{@"test": @"S6", @"status": @"MEASURED", @"parts": parts, @"mainScreenFPS": @(NSScreen.mainScreen.maximumFramesPerSecond),
           @"returnedHome": @(Active() == home), @"evidenceDir": gEvidenceDir});
  });
}

// ---- S12: SCK thumbnails of windows on another Space ----
void SpikeCaptureWindow(uint32_t wid, void (^then)(CGImageRef img, NSDictionary *info)) {
  [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *c, NSError *err) {
    SCWindow *win = nil;
    for (SCWindow *w in c.windows) if (w.windowID == wid) win = w;
    if (!win) { SpikeOnMain(^{ then(NULL, @{@"listed": @NO, @"error": err.description ?: @""}); }); return; }
    SCContentFilter *f = [[SCContentFilter alloc] initWithDesktopIndependentWindow:win];
    SCStreamConfiguration *cfg = [SCStreamConfiguration new];
    cfg.width = (size_t)(win.frame.size.width * 2); cfg.height = (size_t)(win.frame.size.height * 2);
    cfg.showsCursor = NO;
    BOOL onScreen = win.onScreen;
    [SCScreenshotManager captureImageWithFilter:f configuration:cfg completionHandler:^(CGImageRef img, NSError *e) {
      CGImageRetain(img);
      SpikeOnMain(^{
        then(img, @{@"listed": @YES, @"isOnScreen": @(onScreen), @"error": e.description ?: @""});
        CGImageRelease(img);
      });
    }];
  }];
}

NSDictionary *SpikeImageStats(CGImageRef img, CGImageRef other) {
  if (!img) return @{@"image": @NO};
  size_t w = 64, h = 64;
  uint8_t *p1 = calloc(w * h * 4, 1), *p2 = calloc(w * h * 4, 1);
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef c1 = CGBitmapContextCreate(p1, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
  CGContextDrawImage(c1, CGRectMake(0, 0, w, h), img);
  double mean = 0, var = 0, diff = 0;
  for (size_t i = 0; i < w * h; i++) mean += (p1[i * 4] + p1[i * 4 + 1] + p1[i * 4 + 2]) / 3.0;
  mean /= w * h;
  for (size_t i = 0; i < w * h; i++) { double l = (p1[i * 4] + p1[i * 4 + 1] + p1[i * 4 + 2]) / 3.0 - mean; var += l * l; }
  var /= w * h;
  if (other) {
    CGContextRef c2 = CGBitmapContextCreate(p2, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(c2, CGRectMake(0, 0, w, h), other);
    for (size_t i = 0; i < w * h * 4; i++) if (i % 4 != 3) diff += abs(p1[i] - p2[i]);
    diff /= w * h * 3;
    CGContextRelease(c2);
  }
  CGContextRelease(c1); CGColorSpaceRelease(cs); free(p1); free(p2);
  return @{@"image": @YES, @"w": @(CGImageGetWidth(img)), @"h": @(CGImageGetHeight(img)), @"meanLuma": @(mean), @"lumaVar": @(var),
           @"meanAbsDiffVsOther": @(diff)};
}

void TestS12(NSDictionary *a, SpikeDone done) {
  NSArray *desk = Desktops();
  NSArray *needs = Needs(YES, YES, desk.count, 2);
  if (needs.count) { done(SpikeBlocked(@"S12", @"prerequisites missing", needs)); return; }
  uint64_t home = Active();
  NSUInteger hi = [desk indexOfObject:@(home)];
  int dir = (hi + 1 < desk.count) ? 1 : -1;
  SpikeAddCleanup(^{ ReturnHome(home, desk); });
  PostSwipe(dir, 1, 0.000016, 9999, 0.008);
  if (!WaitFor(^{ return (BOOL)(Active() != home); }, 2)) { done(@{@"test": @"S12", @"status": @"FAIL", @"why": @"could not switch Space"}); return; }
  Pump(0.6);
  // A live clock window on the other Space: changes every 100 ms so staleness is visible.
  NSWindow *clock = SpikeMakeWindow(NSMakeRect(200, 200, 420, 260), NSColor.systemIndigoColor, @"FDS S12 clock", YES);
  NSTextField *label = [NSTextField labelWithString:@"0"];
  label.font = [NSFont monospacedDigitSystemFontOfSize:72 weight:NSFontWeightBold];
  label.textColor = NSColor.whiteColor;
  label.frame = NSMakeRect(20, 60, 380, 100);
  [clock.contentView addSubview:label];
  __block long ticks = 0;
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
    label.stringValue = [NSString stringWithFormat:@"%ld", ++ticks];
    clock.backgroundColor = [NSColor colorWithHue:(ticks % 20) / 20.0 saturation:0.7 brightness:0.8 alpha:1];
  }];
  pid_t te = SpikeOpenScratchTextEdit(@"s12-scratch.txt", @"FocusDock spike S12: this TextEdit window lives on another Space.\n", 15);
  SpikeAddCleanup(^{ [timer invalidate]; [clock close]; SpikeQuitApp(te); });
  uint32_t twid = 0;
  for (NSDictionary *x in SpikeWindowsOfPID(te))
    if ([x[(id)kCGWindowLayer] intValue] == 0 && [x[(id)kCGWindowBounds][@"Height"] doubleValue] > 100) { twid = [x[(id)kCGWindowNumber] unsignedIntValue]; break; }
  uint32_t cwid = SpikeWID(clock);
  Pump(0.8);
  NSMutableDictionary *r = [@{@"test": @"S12", @"clockWid": @(cwid), @"textEditWid": @(twid),
                              @"clockSpaces": SpikeSpacesForWindow(cwid), @"homeSpace": @(home)} mutableCopy];
  SpikeCaptureWindow(cwid, ^(CGImageRef onSpace1, NSDictionary *i0) {
    CGImageRef ref = CGImageRetain(onSpace1);
    SpikeWritePNG(ref, [gEvidenceDir stringByAppendingPathComponent:@"s12-clock-same-space.png"], 0.5);
    r[@"controlSameSpace"] = [i0 mutableCopy];
    PostSwipe(-dir, 1, 0.000016, 9999, 0.008);
    WaitFor(^{ return (BOOL)(Active() == home); }, 2);
    Pump(0.8);
    r[@"backHome"] = @(Active() == home);
    SpikeCaptureWindow(cwid, ^(CGImageRef c1, NSDictionary *i1) {
      CGImageRef a1 = CGImageRetain(c1);
      Pump(1.0);
      SpikeCaptureWindow(cwid, ^(CGImageRef c2, NSDictionary *i2) {
        SpikeWritePNG(a1, [gEvidenceDir stringByAppendingPathComponent:@"s12-clock-other-space-1.png"], 0.5);
        SpikeWritePNG(c2, [gEvidenceDir stringByAppendingPathComponent:@"s12-clock-other-space-2.png"], 0.5);
        NSMutableDictionary *cl = [i1 mutableCopy];
        cl[@"first"] = SpikeImageStats(a1, ref);
        cl[@"second"] = SpikeImageStats(c2, a1);
        cl[@"note"] = @"second.meanAbsDiffVsOther > 0 means the off-Space capture is live, not a cached frame";
        r[@"clockOtherSpace"] = cl;
        CGImageRelease(a1); CGImageRelease(ref);
        SpikeCaptureWindow(twid, ^(CGImageRef t1, NSDictionary *it) {
          SpikeWritePNG(t1, [gEvidenceDir stringByAppendingPathComponent:@"s12-textedit-other-space.png"], 0.5);
          NSMutableDictionary *tx = [it mutableCopy];
          tx[@"stats"] = SpikeImageStats(t1, NULL);
          r[@"textEditOtherSpace"] = tx;
          BOOL ok = [cl[@"listed"] boolValue] && [cl[@"first"][@"lumaVar"] doubleValue] > 5 && [tx[@"listed"] boolValue] && [tx[@"stats"][@"lumaVar"] doubleValue] > 5;
          r[@"status"] = ok ? @"PASS" : @"FAIL";
          done(r);
        });
      });
    });
  });
}
