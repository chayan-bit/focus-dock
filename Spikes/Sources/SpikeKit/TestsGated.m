// S5 banner AX tree, S7 AX setFrame timing and proxy seam, S8 Carbon hotkeys under Secure Input,
// S10 accent colour coverage. Each checks its own TCC preconditions and returns BLOCKED without them.
#import "Spike.h"
#import <Carbon/Carbon.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <UserNotifications/UserNotifications.h>

static NSArray *Missing(BOOL ax, BOOL sr) {
  NSMutableArray *n = [NSMutableArray array];
  if (ax && !AXIsProcessTrusted()) [n addObject:@"Accessibility"];
  if (sr && !CGPreflightScreenCaptureAccess()) [n addObject:@"Screen Recording"];
  return n;
}

static id AXGet(AXUIElementRef e, CFStringRef attr) {
  CFTypeRef v = NULL;
  return AXUIElementCopyAttributeValue(e, attr, &v) == kAXErrorSuccess ? CFBridgingRelease(v) : nil;
}

static AXUIElementRef AXFirstWindow(pid_t pid) {
  AXUIElementRef app = AXUIElementCreateApplication(pid);
  NSArray *wins = AXGet(app, kAXWindowsAttribute);
  CFRelease(app);
  return wins.count ? (AXUIElementRef)CFRetain((__bridge CFTypeRef)wins.firstObject) : NULL;
}

static AXError AXSetPoint(AXUIElementRef w, CFStringRef attr, CGPoint p) {
  AXValueRef v = AXValueCreate(kAXValueTypeCGPoint, &p);
  AXError e = AXUIElementSetAttributeValue(w, attr, v);
  CFRelease(v);
  return e;
}

static AXError AXSetSize(AXUIElementRef w, CGSize s) {
  AXValueRef v = AXValueCreate(kAXValueTypeCGSize, &s);
  AXError e = AXUIElementSetAttributeValue(w, kAXSizeAttribute, v);
  CFRelease(v);
  return e;
}

static NSDictionary *Stats(NSArray<NSNumber *> *ms) {
  if (!ms.count) return @{};
  NSArray *s = [ms sortedArrayUsingSelector:@selector(compare:)];
  double sum = 0;
  for (NSNumber *m in ms) sum += m.doubleValue;
  double mean = sum / ms.count;
  return @{@"n": @(ms.count), @"meanMs": @(mean), @"p50Ms": s[s.count / 2], @"p95Ms": s[MIN(s.count - 1, s.count * 95 / 100)],
           @"maxMs": s.lastObject, @"callsPerSecond": @(1000.0 / mean)};
}

// ================= S5 =================
@interface S5Delegate : NSObject <UNUserNotificationCenterDelegate>
@property(nonatomic, copy) NSString *lastAction;
@end
@implementation S5Delegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)c willPresentNotification:(UNNotification *)n
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))h {
  h(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)c didReceiveNotificationResponse:(UNNotificationResponse *)r
         withCompletionHandler:(void (^)(void))h {
  self.lastAction = r.actionIdentifier;
  h();
}
@end

static NSString *Redact(NSString *v, NSString *token) {
  return [v containsString:token] ? v : [NSString stringWithFormat:@"<redacted %lu chars>", (unsigned long)v.length];
}

// Walks an AX subtree; strings that do not contain `token` are redacted to their length.
static NSDictionary *AXDump(AXUIElementRef e, NSString *token, int depth, NSMutableArray *hits) {
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  for (NSString *k in @[@"AXRole", @"AXSubrole", @"AXRoleDescription", @"AXIdentifier"]) {
    id v = AXGet(e, (__bridge CFStringRef)k);
    if ([v isKindOfClass:NSString.class]) d[k] = v;
  }
  for (NSString *k in @[@"AXTitle", @"AXDescription", @"AXValue", @"AXLabel"]) {
    id v = AXGet(e, (__bridge CFStringRef)k);
    if (![v isKindOfClass:NSString.class] || ![v length]) continue;
    d[k] = Redact(v, token);
    if ([v containsString:token]) [hits addObject:(__bridge id)e];
  }
  CFArrayRef acts = NULL;
  if (AXUIElementCopyActionNames(e, &acts) == kAXErrorSuccess && acts && CFArrayGetCount(acts)) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *a in (__bridge NSArray *)acts)
      [names addObject:([a hasPrefix:@"AX"] || [a containsString:@"FDS"]) ? a : @"<custom action, redacted>"];
    d[@"actions"] = names;
  }
  if (acts) CFRelease(acts);
  if (depth < 14) {
    NSArray *kids = AXGet(e, kAXChildrenAttribute);
    if (kids.count) {
      NSMutableArray *k = [NSMutableArray array];
      for (id c in kids) [k addObject:AXDump((__bridge AXUIElementRef)c, token, depth + 1, hits)];
      d[@"children"] = k;
    }
  }
  return d;
}

static NSArray *ActionNames(AXUIElementRef e) {
  CFArrayRef acts = NULL;
  AXUIElementCopyActionNames(e, &acts);
  return acts ? CFBridgingRelease(acts) : @[];
}

static void S5Inspect(NSString *token, S5Delegate *delegate, NSString *postError, SpikeDone done) {
  NSRunningApplication *ncApp = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.notificationcenterui"].firstObject;
  if (!ncApp) { done(@{@"test": @"S5", @"status": @"FAIL", @"why": @"NotificationCenter not running"}); return; }
  AXUIElementRef app = AXUIElementCreateApplication(ncApp.processIdentifier);
  NSMutableArray *hits = [NSMutableArray array];
  NSDictionary *tree = AXDump(app, token, 0, hits);
  NSData *json = [NSJSONSerialization dataWithJSONObject:tree options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
  [json writeToFile:[gEvidenceDir stringByAppendingPathComponent:@"s5-ax-tree.json"] atomically:YES];
  NSMutableDictionary *r = [@{@"test": @"S5", @"postError": postError ?: @"", @"tokenFound": @(hits.count > 0)} mutableCopy];
  // Climb from the text hit to the first ancestor that exposes actions: that is the banner.
  AXUIElementRef banner = NULL;
  NSMutableArray *path = [NSMutableArray array];
  if (hits.count) {
    AXUIElementRef cur = (AXUIElementRef)CFRetain((__bridge CFTypeRef)hits.firstObject);
    for (int i = 0; i < 8 && cur; i++) {
      [path addObject:[NSString stringWithFormat:@"%@/%@", AXGet(cur, kAXRoleAttribute) ?: @"?", AXGet(cur, kAXSubroleAttribute) ?: @"-"]];
      if (ActionNames(cur).count) { banner = cur; break; }
      AXUIElementRef parent = (__bridge_retained AXUIElementRef)AXGet(cur, kAXParentAttribute);
      CFRelease(cur);
      cur = parent;
    }
  }
  r[@"pathFromTextToBanner"] = path;
  if (banner) {
    NSArray *names = ActionNames(banner);
    r[@"bannerRole"] = AXGet(banner, kAXRoleAttribute) ?: @"";
    r[@"bannerSubrole"] = AXGet(banner, kAXSubroleAttribute) ?: @"";
    NSMutableArray *shown = [NSMutableArray array];
    for (NSString *x in names) [shown addObject:([x hasPrefix:@"AX"] || [x containsString:@"FDS"]) ? x : @"<custom, redacted>"];
    r[@"bannerActions"] = shown;
    // Prefer our custom action (proves action buttons are reachable), else AXPress (default action).
    NSString *chosen = nil;
    for (NSString *x in names) if ([x containsString:@"FDS Act"]) chosen = x;
    if (!chosen && [names containsObject:@"AXPress"]) chosen = @"AXPress";
    if (chosen) {
      r[@"performed"] = [chosen hasPrefix:@"AX"] ? chosen : @"custom FDS Act";
      r[@"performError"] = @(AXUIElementPerformAction(banner, (__bridge CFStringRef)chosen));
      SpikePump(2.0);
      r[@"delegateReceived"] = delegate.lastAction ?: @"(nothing)";
    }
    CFRelease(banner);
  }
  CFRelease(app);
  r[@"status"] = (hits.count && delegate.lastAction) ? @"PASS" : hits.count ? @"PARTIAL" : @"FAIL";
  done(r);
}

void TestS5(NSDictionary *a, SpikeDone done) {
  UNUserNotificationCenter *nc = UNUserNotificationCenter.currentNotificationCenter;
  [nc getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *st) {
    SpikeOnMain(^{
      NSMutableArray *n = [Missing(YES, NO) mutableCopy];
      if (st.authorizationStatus != UNAuthorizationStatusAuthorized && st.authorizationStatus != UNAuthorizationStatusProvisional)
        [n addObject:@"Notifications (run notify-auth and click Allow)"];
      if (n.count) { done(SpikeBlocked(@"S5", @"prerequisites missing", n)); return; }
      static S5Delegate *delegate;
      delegate = [S5Delegate new];
      nc.delegate = delegate;
      UNNotificationAction *act = [UNNotificationAction actionWithIdentifier:@"fds.act" title:@"FDS Act" options:UNNotificationActionOptionNone];
      UNNotificationCategory *cat = [UNNotificationCategory categoryWithIdentifier:@"fds.cat" actions:@[act] intentIdentifiers:@[] options:0];
      [nc setNotificationCategories:[NSSet setWithObject:cat]];
      NSString *token = [NSString stringWithFormat:@"FDS-S5-%u", arc4random_uniform(100000)];
      UNMutableNotificationContent *c = [UNMutableNotificationContent new];
      c.title = token;
      c.body = @"FocusDock spike S5 banner";
      c.categoryIdentifier = @"fds.cat";
      SpikeAddCleanup(^{ [nc removeAllDeliveredNotifications]; [nc removeAllPendingNotificationRequests]; });
      [NSApp deactivate];  // banners show for background apps
      UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:token content:c trigger:nil];
      [nc addNotificationRequest:req withCompletionHandler:^(NSError *err) {
        SpikeOnMain(^{
          SpikePump(1.5);
          S5Inspect(token, delegate, err.description, done);
        });
      }];
    });
  }];
}

// ================= S7 =================
static NSString *BigText(void) {
  NSMutableString *s = [NSMutableString string];
  for (int i = 0; i < 30000; i++)
    [s appendFormat:@"%05d FocusDock spike S7 relayout load: the quick brown fox jumps over the lazy dog, again and again and again.\n", i];
  return s;
}

// Per-frame 24x16 luma grid of a region given in display points (top-left origin).
static NSDictionary *(^GridAnalyzer(CGRect region))(const uint8_t *, size_t, size_t, size_t, double) {
  return ^NSDictionary *(const uint8_t *base, size_t w, size_t h, size_t row, double t) {
    const int GX = 24, GY = 16;
    NSMutableArray *g = [NSMutableArray arrayWithCapacity:GX * GY];
    for (int gy = 0; gy < GY; gy++)
      for (int gx = 0; gx < GX; gx++) {
        long x = (long)(region.origin.x + (gx + 0.5) * region.size.width / GX);
        long y = (long)(region.origin.y + (gy + 0.5) * region.size.height / GY);
        int l = 0;
        if (x >= 0 && y >= 0 && x < (long)w && y < (long)h) {
          const uint8_t *p = base + y * row + x * 4;
          l = (p[0] + p[1] + p[2]) / 3;
        }
        [g addObject:@(l)];
      }
    return @{@"t": @(t), @"g": g};
  };
}

static double GridDist(NSArray *a, NSArray *b) {
  double d = 0;
  for (NSUInteger i = 0; i < a.count && i < b.count; i++) d += fabs([a[i] doubleValue] - [b[i] doubleValue]);
  return a.count ? d / a.count : 0;
}

static NSRect NSFromAX(CGRect r) {
  double H = NSScreen.screens.firstObject.frame.size.height;
  return NSMakeRect(r.origin.x, H - r.origin.y - r.size.height, r.size.width, r.size.height);
}

static NSWindow *ImageWindow(CGImageRef img, NSRect frame, NSWindowLevel level) {
  NSWindow *w = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  w.releasedWhenClosed = NO;
  w.opaque = NO;
  w.backgroundColor = NSColor.clearColor;
  w.hasShadow = NO;
  w.ignoresMouseEvents = YES;
  w.level = level;
  NSImageView *iv = [NSImageView imageViewWithImage:[[NSImage alloc] initWithCGImage:img size:frame.size]];
  iv.imageScaling = NSImageScaleAxesIndependently;
  iv.frame = (NSRect){NSZeroPoint, frame.size};
  w.contentView = iv;
  return w;
}

// Captures the display without the target window, cropped to `rect` (display points, top-left).
static void CaptureBehind(uint32_t wid, CGRect rect, void (^then)(CGImageRef)) {
  [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *c, NSError *e) {
    SCDisplay *disp = c.displays.firstObject;
    for (SCDisplay *d in c.displays) if (d.displayID == CGMainDisplayID()) disp = d;
    NSMutableArray *ex = [NSMutableArray array];
    for (SCWindow *w in c.windows) if (w.windowID == wid) [ex addObject:w];
    SCContentFilter *f = [[SCContentFilter alloc] initWithDisplay:disp excludingWindows:ex];
    SCStreamConfiguration *cfg = [SCStreamConfiguration new];
    cfg.width = disp.width * 2; cfg.height = disp.height * 2;
    cfg.showsCursor = NO;
    [SCScreenshotManager captureImageWithFilter:f configuration:cfg completionHandler:^(CGImageRef img, NSError *err) {
      CGImageRef crop = img ? CGImageCreateWithImageInRect(img, CGRectMake(rect.origin.x * 2, rect.origin.y * 2, rect.size.width * 2, rect.size.height * 2)) : NULL;
      SpikeOnMain(^{ then(crop); if (crop) CGImageRelease(crop); });
    }];
  }];
}

static double EaseInOutCos(double t) { return 0.5 - 0.5 * cos(M_PI * t); }

static NSDictionary *SeamMetrics(NSArray *s, NSDictionary *m) {
  if (s.count < 5) return @{};
  NSArray *desk = s.firstObject[@"g"], *fin = s.lastObject[@"g"];
  double sep = MAX(GridDist(desk, fin), 1);
  double tMove = [m[@"tMove"] doubleValue], tLand = [m[@"tLand"] doubleValue];
  int early = 0, dup = 0, seam = 0;
  double maxSeam = 0;
  for (NSDictionary *x in s) {
    double t = [x[@"t"] doubleValue];
    // In the first 100 ms of the animation the proxy has not reached B yet; B should still show the desktop.
    if (t > tMove && t < MIN(tLand, tMove + 0.10)) {
      early++;
      if (GridDist(x[@"g"], fin) < GridDist(x[@"g"], desk)) dup++;
    }
    if (t >= tLand) {
      double dd = GridDist(x[@"g"], fin) / sep;
      if (dd > 0.15) seam++;
      maxSeam = MAX(maxSeam, dd);
    }
  }
  return @{@"desktopVsWindowSeparation": @(sep), @"framesInFirst100ms": @(early), @"duplicateFramesInFirst100ms": @(dup),
           @"seamFramesAfterLanding": @(seam), @"maxSeamFraction": @(maxSeam)};
}

// One proxy move A -> B of the real window, recorded over region B.
static void ProxyMove(AXUIElementRef win, uint32_t wid, CGRect A, CGRect B, BOOL covered, void (^then)(NSDictionary *)) {
  SpikeCaptureWindow(wid, ^(CGImageRef shot, NSDictionary *info) {
    if (!shot) { then(@{@"error": @"window capture failed", @"info": info}); return; }
    CGImageRef W = CGImageRetain(shot);
    void (^run)(CGImageRef) = ^(CGImageRef behind) {
      NSWindow *cover = behind ? ImageWindow(behind, NSFromAX(B), NSFloatingWindowLevel) : nil;
      NSWindow *proxy = ImageWindow(W, NSFromAX(A), NSFloatingWindowLevel + 1);
      SpikeRecorder *rec = [SpikeRecorder new];
      rec.analyzer = GridAnalyzer(B);
      [rec startOnMainDisplayFPS:120 completion:^(NSError *err) {
        [cover orderFrontRegardless];
        [proxy orderFrontRegardless];
        SpikePump(0.3);
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        double t0 = CACurrentMediaTime();
        m[@"tMove"] = @(t0);
        m[@"axMoveError"] = @(AXSetPoint(win, kAXPositionAttribute, B.origin));
        m[@"axMoveMs"] = @((CACurrentMediaTime() - t0) * 1000);
        double dur = 0.22, start = CACurrentMediaTime();
        for (;;) {
          double p = MIN(1.0, (CACurrentMediaTime() - start) / dur), e = EaseInOutCos(p);
          CGRect r = CGRectMake(A.origin.x + (B.origin.x - A.origin.x) * e, A.origin.y + (B.origin.y - A.origin.y) * e, A.size.width, A.size.height);
          [proxy setFrame:NSFromAX(r) display:YES];
          if (p >= 1) break;
          SpikePump(1.0 / 120);
        }
        m[@"tLand"] = @(CACurrentMediaTime());
        [cover orderOut:nil];
        for (int i = 1; i <= 8; i++) { proxy.alphaValue = 1.0 - i / 8.0; SpikePump(0.015); }
        [proxy orderOut:nil];
        m[@"tFadeEnd"] = @(CACurrentMediaTime());
        SpikePump(0.5);
        [rec stop:^{
          NSArray *s = [rec.samples copy];
          NSMutableDictionary *r = [m mutableCopy];
          r[@"covered"] = @(covered);
          r[@"frames"] = @(s.count);
          r[@"recorderError"] = err.description ?: @"";
          [r addEntriesFromDictionary:SeamMetrics(s, m)];
          NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"meta": r, @"samples": s} options:0 error:nil];
          [d writeToFile:[gEvidenceDir stringByAppendingPathComponent:covered ? @"s7-proxy-covered.json" : @"s7-proxy-spec.json"] atomically:YES];
          [proxy close];
          [cover close];
          CGImageRelease(W);
          then(r);
        }];
      }];
    };
    if (covered) CaptureBehind(wid, B, ^(CGImageRef behind) { run(behind); });
    else run(NULL);
  });
}

void TestS7(NSDictionary *a, SpikeDone done) {
  NSArray *needs = Missing(YES, YES);
  if (needs.count) { done(SpikeBlocked(@"S7", @"AX setFrame needs Accessibility; the SCK proxy needs Screen Recording", needs)); return; }
  pid_t te = SpikeOpenScratchTextEdit(@"s7-heavy.txt", BigText(), 20);
  SpikeAddCleanup(^{ SpikeQuitApp(te); });
  SpikePump(1.5);
  AXUIElementRef win = AXFirstWindow(te);
  uint32_t wid = SpikeMainWindowOfPID(te);
  if (!win || !wid) { done(@{@"test": @"S7", @"status": @"FAIL", @"why": @"no TextEdit window via AX"}); return; }
  CGRect A = CGRectMake(80, 120, 900, 640);
  AXSetPoint(win, kAXPositionAttribute, A.origin);
  AXSetSize(win, A.size);
  SpikePump(1.0);
  NSMutableArray *sizeMs = [NSMutableArray array], *posMs = [NSMutableArray array];
  SpikeRecorder *rec = [SpikeRecorder new];
  rec.analyzer = ^NSDictionary *(const uint8_t *b, size_t w, size_t h, size_t r, double t) { return @{@"t": @(t)}; };
  [rec startOnMainDisplayFPS:120 completion:^(NSError *err) {
    SpikePump(0.3);
    NSInteger f0 = rec.framesSeen;
    double t0 = CACurrentMediaTime();
    for (int i = 0; i < 60; i++) {
      double s = CACurrentMediaTime();
      AXSetSize(win, (i % 2) ? A.size : CGSizeMake(A.size.width + 100, A.size.height + 60));
      [sizeMs addObject:@((CACurrentMediaTime() - s) * 1000)];
    }
    double sizeWall = CACurrentMediaTime() - t0;
    SpikePump(0.05);
    NSInteger framesDuringSize = rec.framesSeen - f0;
    SpikePump(0.5);
    double t1 = CACurrentMediaTime();
    for (int i = 0; i < 60; i++) {
      double s = CACurrentMediaTime();
      AXSetPoint(win, kAXPositionAttribute, (i % 2) ? A.origin : CGPointMake(A.origin.x + 40, A.origin.y + 20));
      [posMs addObject:@((CACurrentMediaTime() - s) * 1000)];
    }
    double posWall = CACurrentMediaTime() - t1;
    [rec stop:^{
      AXSetPoint(win, kAXPositionAttribute, A.origin);
      AXSetSize(win, A.size);
      SpikePump(0.8);
      NSMutableDictionary *r = [@{@"test": @"S7", @"heavyApp": @"TextEdit, 30000-line wrapped plain text",
        @"resize60": Stats(sizeMs), @"resize60WallS": @(sizeWall), @"move60": Stats(posMs), @"move60WallS": @(posWall),
        @"screenFramesDuringResizeLoop": @(framesDuringSize), @"recorderError": err.description ?: @""} mutableCopy];
      CGRect B = CGRectMake(A.origin.x + 300, A.origin.y + 80, A.size.width, A.size.height);
      ProxyMove(win, wid, A, B, NO, ^(NSDictionary *spec) {
        r[@"proxySpecVariant"] = spec;
        AXSetPoint(win, kAXPositionAttribute, A.origin);
        SpikePump(1.0);
        ProxyMove(win, wid, A, B, YES, ^(NSDictionary *cov) {
          r[@"proxyCoveredVariant"] = cov;
          AXSetPoint(win, kAXPositionAttribute, A.origin);
          CFRelease(win);
          r[@"status"] = @"MEASURED";
          done(r);
        });
      });
    }];
  }];
}

// ================= S8 =================
static int gHotKeyHits;
static OSStatus HotKeyHandler(EventHandlerCallRef next, EventRef ev, void *ud) { gHotKeyHits++; return noErr; }

static void PostF18(void) {
  CGEventRef d = CGEventCreateKeyboardEvent(NULL, kVK_F18, true), u = CGEventCreateKeyboardEvent(NULL, kVK_F18, false);
  CGEventPost(kCGHIDEventTap, d);
  CGEventPost(kCGHIDEventTap, u);
  CFRelease(d);
  CFRelease(u);
}

static BOOL SecureNow(void) { return SLS.IsSecureEventInputSet ? SLS.IsSecureEventInputSet() : IsSecureEventInputEnabled(); }

void TestS8(NSDictionary *a, SpikeDone done) {
  NSArray *needs = Missing(YES, NO);
  if (needs.count) { done(SpikeBlocked(@"S8", @"posting the hotkey keystroke needs Accessibility", needs)); return; }
  EventTypeSpec spec = {kEventClassKeyboard, kEventHotKeyPressed};
  EventHandlerRef handler = NULL;
  InstallApplicationEventHandler(NewEventHandlerUPP(HotKeyHandler), 1, &spec, NULL, &handler);
  EventHotKeyRef hk = NULL;
  OSStatus reg = RegisterEventHotKey(kVK_F18, 0, (EventHotKeyID){'FDSk', 1}, GetApplicationEventTarget(), 0, &hk);
  SpikeAddCleanup(^{ if (hk) UnregisterEventHotKey(hk); if (handler) RemoveEventHandler(handler); });
  NSMutableDictionary *r = [@{@"test": @"S8", @"registerStatus": @(reg), @"hotkey": @"F18, no modifiers"} mutableCopy];
  r[@"secureBefore"] = @(SecureNow());
  gHotKeyHits = 0;
  PostF18();
  SpikePump(0.6);
  r[@"firedWithoutSecureInput"] = @(gHotKeyHits);
  NSString *line = nil;
  NSTask *helper = SpikeSpawnHelper(@"helper-secure-input", @[@"hold=6"], &line);
  SpikeAddCleanup(^{ if (helper.running) [helper terminate]; });
  SpikePump(0.8);
  r[@"helperLine"] = line ?: @"";
  r[@"secureDuring"] = @(SecureNow());
  r[@"frontmostDuring"] = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == helper.processIdentifier ? @"secure-input helper" : @"other";
  gHotKeyHits = 0;
  PostF18();
  SpikePump(0.6);
  r[@"firedWithSecureInput"] = @(gHotKeyHits);
  [helper terminate];
  [helper waitUntilExit];
  SpikePump(0.5);
  r[@"secureAfter"] = @(SecureNow());
  BOOL measured = [r[@"secureDuring"] boolValue] && [r[@"firedWithoutSecureInput"] intValue] > 0;
  r[@"status"] = !measured ? @"FAIL" : ([r[@"firedWithSecureInput"] intValue] > 0 ? @"PASS" : @"FAIL");
  r[@"note"] = @"F18 posted at the HID tap; a physical key press is not tested";
  done(r);
}

// ================= S10 =================
static id AccentValue(void) {
  return CFBridgingRelease(CFPreferencesCopyValue(CFSTR("AppleAccentColor"), kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
}

static void SetAccent(id value) {
  CFPreferencesSetValue(CFSTR("AppleAccentColor"), (__bridge CFPropertyListRef)value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
  CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
  for (NSString *n in @[@"AppleColorPreferencesChangedNotification", @"AppleAquaColorVariantChanged"])
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:n object:nil userInfo:nil deliverImmediately:YES];
}

static NSDictionary *Diff(CGImageRef x, CGImageRef y) {
  if (!x || !y) return @{@"missing": @YES};
  size_t w = 160, h = 100;
  uint8_t *p = calloc(w * h * 4, 1), *q = calloc(w * h * 4, 1);
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef a = CGBitmapContextCreate(p, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
  CGContextRef b = CGBitmapContextCreate(q, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
  CGContextDrawImage(a, CGRectMake(0, 0, w, h), x);
  CGContextDrawImage(b, CGRectMake(0, 0, w, h), y);
  long changed = 0, redX = 0, redY = 0;
  for (size_t i = 0; i < w * h; i++) {
    uint8_t *u = p + i * 4, *v = q + i * 4;
    if (abs(u[0] - v[0]) + abs(u[1] - v[1]) + abs(u[2] - v[2]) > 40) changed++;
    if (u[0] > 150 && u[1] < 100 && u[2] < 100) redX++;
    if (v[0] > 150 && v[1] < 100 && v[2] < 100) redY++;
  }
  CGContextRelease(a); CGContextRelease(b); CGColorSpaceRelease(cs); free(p); free(q);
  return @{@"changedFraction": @((double)changed / (w * h)), @"redPixelsBefore": @(redX), @"redPixelsAfter": @(redY)};
}

static NSWindow *ControlsWindow(void) {
  NSWindow *w = SpikeMakeWindow(NSMakeRect(120, 300, 420, 260), nil, @"FDS S10 controls", YES);
  NSView *v = w.contentView;
  NSButton *check = [NSButton checkboxWithTitle:@"Checkbox" target:nil action:nil];
  check.state = NSControlStateValueOn; check.frame = NSMakeRect(20, 210, 160, 24);
  NSButton *push = [NSButton buttonWithTitle:@"Default" target:nil action:nil];
  push.keyEquivalent = @"\r"; push.frame = NSMakeRect(200, 205, 120, 32);
  NSSlider *slider = [NSSlider sliderWithValue:60 minValue:0 maxValue:100 target:nil action:nil];
  slider.frame = NSMakeRect(20, 165, 380, 24);
  NSSegmentedControl *seg = [NSSegmentedControl segmentedControlWithLabels:@[@"One", @"Two", @"Three"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
  seg.selectedSegment = 1; seg.frame = NSMakeRect(20, 125, 240, 28);
  NSSwitch *sw = [NSSwitch new]; sw.state = NSControlStateValueOn; sw.frame = NSMakeRect(290, 125, 60, 28);
  NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(20, 20, 380, 90)];
  tv.string = @"Selected text uses the highlight colour, which follows the accent when AppleHighlightColor is unset.";
  for (NSView *x in @[check, push, slider, seg, sw, tv]) [v addSubview:x];
  [NSApp activateIgnoringOtherApps:YES];
  [w makeKeyAndOrderFront:nil];
  [w makeFirstResponder:tv];
  [tv setSelectedRange:NSMakeRange(0, 40)];
  return w;
}

// Launches an app only if it is not already running (never touches a session the user has open).
static pid_t LaunchIfNotRunning(NSString *bundleID, NSURL *openURL, NSMutableArray *skipped) {
  if ([NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID].count) { [skipped addObject:bundleID]; return 0; }
  NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundleID];
  if (!app) { [skipped addObject:bundleID]; return 0; }
  NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
  cfg.arguments = @[@"-ApplePersistenceIgnoreState", @"YES"];
  __block pid_t pid = 0;
  __block BOOL fin = NO;
  void (^h)(NSRunningApplication *, NSError *) = ^(NSRunningApplication *ra, NSError *e) { pid = ra.processIdentifier; fin = YES; };
  if (openURL) [NSWorkspace.sharedWorkspace openURLs:@[openURL] withApplicationAtURL:app configuration:cfg completionHandler:h];
  else [NSWorkspace.sharedWorkspace openApplicationAtURL:app configuration:cfg completionHandler:h];
  for (int i = 0; i < 100 && (!fin || !SpikeMainWindowOfPID(pid)); i++) SpikePump(0.1);
  return pid;
}

static void CaptureAll(NSArray<NSDictionary *> *targets, NSString *phase, NSMutableDictionary *store, NSUInteger i, dispatch_block_t then) {
  if (i >= targets.count) { then(); return; }
  NSDictionary *t = targets[i];
  SpikeCaptureWindow([t[@"wid"] unsignedIntValue], ^(CGImageRef img, NSDictionary *info) {
    if (img) {
      store[[NSString stringWithFormat:@"%@/%@", t[@"name"], phase]] = (__bridge id)img;
      SpikeWritePNG(img, [gEvidenceDir stringByAppendingPathComponent:[NSString stringWithFormat:@"s10-%@-%@.png", t[@"name"], phase]], 0.35);
    }
    CaptureAll(targets, phase, store, i + 1, then);
  });
}

static void SelectTextViaAX(pid_t pid) {
  AXUIElementRef tw = AXFirstWindow(pid);
  if (!tw) return;
  NSMutableArray *stack = [NSMutableArray arrayWithObject:(__bridge id)tw];
  while (stack.count) {
    id held = stack.lastObject;  // strong ref: removeLastObject would free the element otherwise
    [stack removeLastObject];
    AXUIElementRef e = (__bridge AXUIElementRef)held;
    if ([AXGet(e, kAXRoleAttribute) isEqual:@"AXTextArea"]) {
      CFRange range = CFRangeMake(0, 40);
      AXValueRef v = AXValueCreate(kAXValueTypeCFRange, &range);
      AXUIElementSetAttributeValue(e, kAXSelectedTextRangeAttribute, v);
      CFRelease(v);
      break;
    }
    for (id c in AXGet(e, kAXChildrenAttribute) ?: @[]) [stack addObject:c];
  }
  CFRelease(tw);
}

// Closes only the Finder window we opened, matched by its CG frame among Finder's AX windows.
static void CloseFinderWindow(pid_t finder, uint32_t fwid) {
  NSDictionary *b = SpikeWindowInfo(fwid)[(id)kCGWindowBounds];
  if (!b) return;
  AXUIElementRef app = AXUIElementCreateApplication(finder);
  for (id w in AXGet(app, kAXWindowsAttribute) ?: @[]) {
    CGPoint p = CGPointZero;
    id pos = AXGet((__bridge AXUIElementRef)w, kAXPositionAttribute);
    if (pos) AXValueGetValue((__bridge AXValueRef)pos, kAXValueTypeCGPoint, &p);
    if (fabs(p.x - [b[@"X"] doubleValue]) < 1 && fabs(p.y - [b[@"Y"] doubleValue]) < 1) {
      id close = AXGet((__bridge AXUIElementRef)w, kAXCloseButtonAttribute);
      if (close) AXUIElementPerformAction((__bridge AXUIElementRef)close, kAXPressAction);
    }
  }
  CFRelease(app);
}

void TestS10(NSDictionary *a, SpikeDone done) {
  NSArray *needs = Missing(YES, YES);
  if (needs.count) { done(SpikeBlocked(@"S10", @"before/after captures need Screen Recording; TextEdit selection and closing Finder need Accessibility", needs)); return; }
  id original = AccentValue();
  NSMutableDictionary *r = [@{@"test": @"S10", @"originalAccent": original ?: @"unset"} mutableCopy];
  SpikeAddCleanup(^{ SetAccent(original); });  // exact restore (unset means delete), also on timeout
  NSMutableArray *skipped = [NSMutableArray array], *targets = [NSMutableArray array];
  NSWindow *controls = ControlsWindow();
  SpikeAddCleanup(^{ [controls close]; });
  SpikePump(0.5);
  [targets addObject:@{@"name": @"spike-appkit", @"wid": @(SpikeWID(controls))}];
  pid_t te = SpikeOpenScratchTextEdit(@"s10-scratch.txt", @"FocusDock spike S10: selected text shows the highlight colour.\nSecond line.\n", 15);
  SpikeAddCleanup(^{ SpikeQuitApp(te); });
  SelectTextViaAX(te);
  if (SpikeMainWindowOfPID(te)) [targets addObject:@{@"name": @"textedit", @"wid": @(SpikeMainWindowOfPID(te))}];
  pid_t fb = LaunchIfNotRunning(@"com.apple.FontBook", nil, skipped);
  if (fb) { SpikeAddCleanup(^{ SpikeQuitApp(fb); }); [targets addObject:@{@"name": @"fontbook", @"wid": @(SpikeMainWindowOfPID(fb))}]; }
  pid_t ss = LaunchIfNotRunning(@"com.apple.systempreferences", [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Appearance-Settings.extension"], skipped);
  if (ss) { SpikeAddCleanup(^{ SpikeQuitApp(ss); }); SpikePump(1.0); [targets addObject:@{@"name": @"system-settings", @"wid": @(SpikeMainWindowOfPID(ss))}]; }
  pid_t finder = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject.processIdentifier;
  NSSet *finderBefore = [NSSet setWithArray:[SpikeWindowsOfPID(finder) valueForKey:(id)kCGWindowNumber]];
  [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:@"/Applications"]];
  SpikePump(1.5);
  uint32_t fwid = 0;
  for (NSDictionary *w in SpikeWindowsOfPID(finder))
    if ([w[(id)kCGWindowLayer] intValue] == 0 && ![finderBefore containsObject:w[(id)kCGWindowNumber]] && [w[(id)kCGWindowBounds][@"Height"] doubleValue] > 100)
      fwid = [w[(id)kCGWindowNumber] unsignedIntValue];
  if (fwid) {
    [targets addObject:@{@"name": @"finder", @"wid": @(fwid)}];
    SpikeAddCleanup(^{ CloseFinderWindow(finder, fwid); });
  } else [skipped addObject:@"com.apple.finder (no new window)"];
  [NSApp activateIgnoringOtherApps:YES];
  [controls makeKeyAndOrderFront:nil];
  SpikePump(0.8);
  r[@"targets"] = [targets valueForKey:@"name"];
  r[@"skippedAlreadyRunning"] = skipped;
  NSMutableDictionary *img = [NSMutableDictionary dictionary];
  CaptureAll(targets, @"before", img, 0, ^{
    SetAccent(@0);  // red: maximal contrast with the default blue
    r[@"accentWhileTesting"] = AccentValue() ?: @"unset";
    SpikePump(2.5);
    CaptureAll(targets, @"after", img, 0, ^{
      SetAccent(original);
      SpikePump(2.5);
      CaptureAll(targets, @"restored", img, 0, ^{
        NSMutableDictionary *per = [NSMutableDictionary dictionary];
        for (NSDictionary *t in targets) {
          NSString *n = t[@"name"];
          CGImageRef b = (__bridge CGImageRef)img[[n stringByAppendingString:@"/before"]];
          NSMutableDictionary *d = [Diff(b, (__bridge CGImageRef)img[[n stringByAppendingString:@"/after"]]) mutableCopy];
          d[@"restoredVsBefore"] = Diff(b, (__bridge CGImageRef)img[[n stringByAppendingString:@"/restored"]])[@"changedFraction"] ?: @-1;
          per[n] = d;
        }
        r[@"perApp"] = per;
        id now = AccentValue();
        r[@"accentAfterRestore"] = now ?: @"unset";
        r[@"restoreVerified"] = @((original == nil && now == nil) || [original isEqual:now]);
        r[@"status"] = [r[@"restoreVerified"] boolValue] ? @"MEASURED" : @"FAIL";
        done(r);
      });
    });
  });
}
