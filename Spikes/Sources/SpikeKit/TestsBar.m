// S4 status-item Cmd-drag, S9 status-item mirror while Apple's bar is auto-hidden.
#import "Spike.h"

static void Pump(double s) { SpikePump(s); }

static NSDictionary *ItemInfo(NSStatusItem *item) {
  NSWindow *w = item.button.window;
  uint32_t wid = (uint32_t)w.windowNumber;
  NSDictionary *cg = SpikeWindowInfo(wid);
  return @{@"wid": @(wid), @"nsFrame": NSStringFromRect(w.frame), @"cgLayer": cg[(id)kCGWindowLayer] ?: NSNull.null,
           @"cgOwnerPID": cg[(id)kCGWindowOwnerPID] ?: NSNull.null, @"cgOwnerName": cg[(id)kCGWindowOwnerName] ?: NSNull.null,
           @"cgBounds": cg[(id)kCGWindowBounds] ?: NSNull.null, @"ourPID": @(getpid())};
}

// Every window at status-ish layers (owner names and bounds need no Screen Recording).
static NSArray *StatusLayerInventory(void) {
  NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
  NSMutableArray *out = [NSMutableArray array];
  for (NSDictionary *w in list) {
    int layer = [w[(id)kCGWindowLayer] intValue];
    if (layer < 23 || layer > 27) continue;
    BOOL ours = [w[(id)kCGWindowOwnerPID] intValue] == getpid();
    [out addObject:@{@"layer": @(layer), @"wid": w[(id)kCGWindowNumber], @"ours": @(ours),
                     @"owner": ours ? @"FocusDockSpike" : ([@[@"MenuBarAgent", @"Window Server", @"SystemUIServer", @"ControlCenter"] containsObject:w[(id)kCGWindowOwnerName] ?: @""] ? w[(id)kCGWindowOwnerName] : @"third-party"),
                     @"bounds": w[(id)kCGWindowBounds] ?: @{}}];
  }
  return out;
}

static NSArray *MenuBarWindowList(int target) {
  if (!SLS.GetProcessMenuBarWindowList || !SLS.GetOnScreenWindowCount) return @[];
  int count = 0;
  SLS.GetOnScreenWindowCount(gCID, target, &count);
  if (count <= 0) count = 512;
  uint32_t *list = calloc((size_t)count, sizeof(uint32_t));
  int out = 0;
  CGError e = SLS.GetProcessMenuBarWindowList(gCID, target, count, list, &out);
  NSMutableArray *r = [NSMutableArray array];
  for (int i = 0; i < out; i++) [r addObject:@(list[i])];
  free(list);
  return e ? @[@{@"error": @(e)}] : r;
}

static void PostMouse(CGEventType type, CGPoint p, CGEventFlags flags, uint32_t wid) {
  CGEventRef e = CGEventCreateMouseEvent(NULL, type, p, kCGMouseButtonLeft);
  CGEventSetFlags(e, flags);
  if (wid) {  // Ice tags menu-bar-item events with the item window (fields 0x33, 91, 92)
    CGEventSetIntegerValueField(e, kCGMouseEventWindowUnderMousePointer, wid);
    CGEventSetIntegerValueField(e, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, wid);
    CGEventSetIntegerValueField(e, (CGEventField)0x33, wid);
  }
  CGEventPost(kCGHIDEventTap, e);
  CFRelease(e);
}

// On 27 the item's NSStatusBarWindow frame is a placeholder; AX on our own app has the real frame.
static NSDictionary *AXItemFrames(void) {
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  AXUIElementRef app = AXUIElementCreateApplication(getpid());
  CFTypeRef extras = NULL, kids = NULL;
  AXUIElementCopyAttributeValue(app, CFSTR("AXExtrasMenuBar"), &extras);
  if (extras) AXUIElementCopyAttributeValue(extras, kAXChildrenAttribute, &kids);
  for (CFIndex i = 0; kids && i < CFArrayGetCount(kids); i++) {
    AXUIElementRef e = (AXUIElementRef)CFArrayGetValueAtIndex(kids, i);
    CFTypeRef title = NULL, pos = NULL, size = NULL;
    AXUIElementCopyAttributeValue(e, kAXTitleAttribute, &title);
    AXUIElementCopyAttributeValue(e, kAXPositionAttribute, &pos);
    AXUIElementCopyAttributeValue(e, kAXSizeAttribute, &size);
    CGPoint p = CGPointZero; CGSize z = CGSizeZero;
    if (pos) AXValueGetValue(pos, kAXValueTypeCGPoint, &p);
    if (size) AXValueGetValue(size, kAXValueTypeCGSize, &z);
    NSString *key = title ? (__bridge NSString *)title : [NSString stringWithFormat:@"item%ld", (long)i];
    out[key] = NSStringFromRect(NSMakeRect(p.x, p.y, z.width, z.height));
    if (title) CFRelease(title);
    if (pos) CFRelease(pos);
    if (size) CFRelease(size);
  }
  if (kids) CFRelease(kids);
  if (extras) CFRelease(extras);
  CFRelease(app);
  return out;
}

void TestS4(NSDictionary *a, SpikeDone done) {
  NSStatusItem *A = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
  A.autosaveName = @"FDSpikeA";
  A.button.title = @"FDS-A";
  NSStatusItem *B = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
  B.autosaveName = @"FDSpikeB";
  B.button.title = @"FDS-B";
  NSString *dom = NSBundle.mainBundle.bundleIdentifier;
  SpikeAddCleanup(^{
    [NSStatusBar.systemStatusBar removeStatusItem:A];
    [NSStatusBar.systemStatusBar removeStatusItem:B];
    for (NSString *k in NSUserDefaults.standardUserDefaults.dictionaryRepresentation.allKeys)
      if ([k hasPrefix:@"NSStatusItem"] && [k containsString:@"FDSpike"]) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
    [NSUserDefaults.standardUserDefaults synchronize];
  });
  Pump(1.0);
  NSMutableDictionary *r = [@{@"test": @"S4", @"itemA": ItemInfo(A), @"itemB": ItemInfo(B),
    @"menuBarWindowsOurs": MenuBarWindowList(gCID), @"statusLayerInventory": StatusLayerInventory(),
    @"buttonWindowClass": NSStringFromClass(A.button.window.class) ?: @"nil",
    @"axOwnItems": ({ AXUIElementRef app = AXUIElementCreateApplication(getpid()); CFTypeRef extras = NULL;
                      AXError e = AXUIElementCopyAttributeValue(app, CFSTR("AXExtrasMenuBar"), &extras);
                      CFIndex n = 0; if (!e && extras) { CFTypeRef kids = NULL; AXUIElementCopyAttributeValue(extras, kAXChildrenAttribute, &kids); n = kids ? CFArrayGetCount(kids) : 0; if (kids) CFRelease(kids); CFRelease(extras); }
                      CFRelease(app); @{@"axError": @(e), @"children": @(n)}; }), @"menuBarWindowsAllCount": @(MenuBarWindowList(0).count),
    @"prefsBefore": ({ NSMutableDictionary *p = [NSMutableDictionary dictionary];
                       for (NSString *k in NSUserDefaults.standardUserDefaults.dictionaryRepresentation)
                         if ([k hasPrefix:@"NSStatusItem"]) p[k] = [NSUserDefaults.standardUserDefaults objectForKey:k];
                       p; }), @"domain": dom ?: @""} mutableCopy];
  if (!AXIsProcessTrusted()) {
    NSMutableDictionary *b = [SpikeBlocked(@"S4", @"posting the Cmd-drag needs Accessibility", @[@"Accessibility"]) mutableCopy];
    [b addEntriesFromDictionary:r];
    b[@"status"] = @"BLOCKED";
    done(b);
    return;
  }
  // Drag the left item to just past the other one's centre: crosses only our own items.
  CGEventRef cur = CGEventCreate(NULL); CGPoint saved = CGEventGetLocation(cur); CFRelease(cur);
  SpikeAddCleanup(^{ CGWarpMouseCursorPosition(saved); });
  NSDictionary *f0 = AXItemFrames();
  r[@"axFramesBefore"] = f0;
  NSRect ra = NSRectFromString(f0[@"FDS-A"] ?: @"{{0,0},{0,0}}"), rb = NSRectFromString(f0[@"FDS-B"] ?: @"{{0,0},{0,0}}");
  if (NSIsEmptyRect(ra) || NSIsEmptyRect(rb)) { r[@"status"] = @"FAIL"; r[@"why"] = @"no AX frames for our items"; done(r); return; }
  NSRect left = NSMinX(ra) < NSMinX(rb) ? ra : rb, right = NSMinX(ra) < NSMinX(rb) ? rb : ra;
  CGPoint from = CGPointMake(NSMidX(left), NSMidY(left)), to = CGPointMake(NSMidX(right) + NSWidth(right) * 0.5 + 4, NSMidY(right));
  PostMouse(kCGEventMouseMoved, from, 0, 0);
  SpikePump(0.1);
  PostMouse(kCGEventLeftMouseDown, from, kCGEventFlagMaskCommand, 0);
  SpikePump(0.15);
  for (int i = 1; i <= 12; i++) {
    PostMouse(kCGEventLeftMouseDragged, CGPointMake(from.x + (to.x - from.x) * i / 12.0, from.y), kCGEventFlagMaskCommand, 0);
    SpikePump(0.03);
  }
  PostMouse(kCGEventLeftMouseUp, to, kCGEventFlagMaskCommand, 0);
  SpikePump(1.0);
  CGWarpMouseCursorPosition(saved);
  NSDictionary *f1 = AXItemFrames();
  r[@"axFramesAfter"] = f1;
  double a0 = NSMinX(NSRectFromString(f0[@"FDS-A"])), b0 = NSMinX(NSRectFromString(f0[@"FDS-B"]));
  double a1 = NSMinX(NSRectFromString(f1[@"FDS-A"] ?: @"{{0,0},{0,0}}")), b1 = NSMinX(NSRectFromString(f1[@"FDS-B"] ?: @"{{0,0},{0,0}}"));
  r[@"orderSwapped"] = @((a0 < b0) != (a1 < b1));
  NSMutableDictionary *p = [NSMutableDictionary dictionary];
  for (NSString *k in NSUserDefaults.standardUserDefaults.dictionaryRepresentation)
    if ([k hasPrefix:@"NSStatusItem"]) p[k] = [NSUserDefaults.standardUserDefaults objectForKey:k];
  r[@"prefsAfter"] = p;
  r[@"status"] = [r[@"orderSwapped"] boolValue] ? @"PASS" : @"FAIL";
  done(r);
}

@interface S9Target : NSObject
@property(nonatomic) int hits;
- (void)hit:(id)sender;
@end
@implementation S9Target
- (void)hit:(id)sender { self.hits++; }
@end

// Captures MenuBarAgent's bar window and crops it to our item; then AXPresses the item via our own AX tree.
static void MirrorAndPress(NSString *phase, NSStatusItem *item, S9Target *target, void (^then)(NSDictionary *)) {
  uint32_t bar = 0;
  for (NSDictionary *w in StatusLayerInventory())
    if ([w[@"owner"] isEqual:@"MenuBarAgent"] && [w[@"bounds"][@"Width"] doubleValue] > 600) bar = [w[@"wid"] unsignedIntValue];
  NSRect f = NSRectFromString(AXItemFrames()[item.button.title] ?: @"{{0,0},{0,0}}");  // AX: top-left origin
  SpikeCaptureWindow(bar, ^(CGImageRef img, NSDictionary *info) {
    NSMutableDictionary *r = [@{@"phase": phase, @"barWid": @(bar), @"captureInfo": info ?: @{}, @"itemFrame": NSStringFromRect(f)} mutableCopy];
    if (img) {
      double sx = CGImageGetWidth(img) / NSScreen.screens.firstObject.frame.size.width;
      CGRect crop = CGRectMake(f.origin.x * sx, f.origin.y * sx, f.size.width * sx, f.size.height * sx);
      CGImageRef c = CGImageCreateWithImageInRect(img, crop);
      r[@"itemCropStats"] = SpikeImageStats(c, NULL);
      SpikeWritePNG(c, [gEvidenceDir stringByAppendingPathComponent:[NSString stringWithFormat:@"s9-item-%@.png", phase]], 1.0);
      SpikeWritePNG(img, [gEvidenceDir stringByAppendingPathComponent:[NSString stringWithFormat:@"s9-bar-%@.png", phase]], 0.5);
      if (c) CGImageRelease(c);
    }
    AXUIElementRef app = AXUIElementCreateApplication(getpid());
    CFTypeRef extras = NULL, kids = NULL;
    AXUIElementCopyAttributeValue(app, CFSTR("AXExtrasMenuBar"), &extras);
    if (extras) AXUIElementCopyAttributeValue(extras, kAXChildrenAttribute, &kids);
    int before = target.hits;
    AXError pe = kAXErrorFailure;
    if (kids && CFArrayGetCount(kids)) pe = AXUIElementPerformAction((AXUIElementRef)CFArrayGetValueAtIndex(kids, 0), kAXPressAction);
    SpikePump(0.5);
    r[@"axPressError"] = @(pe);
    r[@"actionFired"] = @(target.hits > before);
    if (kids) CFRelease(kids);
    if (extras) CFRelease(extras);
    CFRelease(app);
    then(r);
  });
}

void TestS9(NSDictionary *a, SpikeDone done) {
  bool autohide = false;
  if (SLS.GetMenuBarAutohideEnabled) SLS.GetMenuBarAutohideEnabled(gCID, &autohide);
  id hide = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("_HIHideMenuBar"), kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
  BOOL hidden = autohide || [hide boolValue];
  NSMutableArray *needs = [NSMutableArray array];
  if (!AXIsProcessTrusted()) [needs addObject:@"Accessibility"];
  if (!CGPreflightScreenCaptureAccess()) [needs addObject:@"Screen Recording"];
  NSMutableDictionary *base = [@{@"test": @"S9", @"menuBarAutohideSPI": @(autohide), @"_HIHideMenuBar": hide ?: NSNull.null} mutableCopy];
  if (needs.count) {
    [base addEntriesFromDictionary:SpikeBlocked(@"S9", hidden ? @"grants missing" : @"bar not auto-hidden, and grants missing for the visible-bar control", needs)];
    if (!hidden) base[@"status"] = @"BLOCKED-USER-SETTING";
    done(base);
    return;
  }
  S9Target *target = [S9Target new];
  NSStatusItem *item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
  item.button.title = @"FDS-S9";
  item.button.target = target;
  item.button.action = @selector(hit:);
  SpikeAddCleanup(^{ [NSStatusBar.systemStatusBar removeStatusItem:item]; });
  SpikePump(1.0);
  // Control with the bar as it is now; with auto-hide on this is the hidden state (cursor away from the top edge).
  MirrorAndPress(hidden ? @"hidden" : @"visible-control", item, target, ^(NSDictionary *r1) {
    base[@"result"] = r1;
    BOOL ok = [r1[@"itemCropStats"][@"lumaVar"] doubleValue] > 5 && [r1[@"actionFired"] boolValue];
    base[@"status"] = hidden ? (ok ? @"PASS" : @"FAIL") : @"BLOCKED-USER-SETTING";
    if (!hidden) base[@"why"] = @"bar is not auto-hidden; only the visible-bar control ran";
    done(base);
  });
}
