// env, S3 (universal-owner gate), S13 (usernoted DB), helper processes, notification auth.
#import "Spike.h"
#import <Carbon/Carbon.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <dlfcn.h>
#import <UserNotifications/UserNotifications.h>

static id PrefAny(NSString *key, NSString *app) {
  return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)(app ?: (id)kCFPreferencesAnyApplication),
                                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
}

static id PrefApp(NSString *key, NSString *app) {
  return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)app));
}

static NSDictionary *Responsible(void) {
  pid_t (*resp)(pid_t) = dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid");
  pid_t r = resp ? resp(getpid()) : -1;
  NSRunningApplication *ra = [NSRunningApplication runningApplicationWithProcessIdentifier:r];
  return @{@"self": @(getpid()), @"responsiblePID": @(r), @"responsibleIsSelf": @(r == getpid()),
           @"responsibleBundle": ra.bundleIdentifier ?: @"(not an app)"};
}

void TestEnv(NSDictionary *a, SpikeDone done) {
  bool autohide = false;
  if (SLS.GetMenuBarAutohideEnabled) SLS.GetMenuBarAutohideEnabled(gCID, &autohide);
  NSMutableDictionary *hot = [NSMutableDictionary dictionary];
  // 32 Mission Control, 79/81 move left/right a Space, 118-121 switch to Desktop 1-4, 1/2 Cmd-Tab.
  for (NSNumber *h in @[@1, @2, @32, @79, @81, @118, @119, @120, @121])
    hot[h.stringValue] = SLS.IsSymbolicHotKeyEnabled ? @(SLS.IsSymbolicHotKeyEnabled(h.intValue)) : NSNull.null;
  NSScreen *main = NSScreen.mainScreen;
  done(@{
    @"test": @"env", @"status": @"INFO",
    @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
    @"permissions": SpikePermissions(),
    @"responsibility": Responsible(),
    @"spaces": SpikeUserSpaces(),
    @"activeSpace": @(SLS.GetActiveSpace ? SLS.GetActiveSpace(gCID) : 0),
    @"screens": @(NSScreen.screens.count),
    @"mainScreenFPS": @(main.maximumFramesPerSecond),
    @"mainScreenPoints": NSStringFromSize(main.frame.size),
    @"backingScale": @(main.backingScaleFactor),
    @"menuBarAutohideSPI": @(autohide),
    @"_HIHideMenuBar": PrefAny(@"_HIHideMenuBar", nil) ?: NSNull.null,
    @"AppleMenuBarVisibleInFullscreen": PrefAny(@"AppleMenuBarVisibleInFullscreen", nil) ?: NSNull.null,
    @"secureInput": @(SLS.IsSecureEventInputSet ? SLS.IsSecureEventInputSet() : -1),
    @"IsSecureEventInputEnabled": @(IsSecureEventInputEnabled()),
    @"symbolicHotKeysEnabled": hot,
    @"reduceMotion": @(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion),
    @"dockMagnification": PrefApp(@"magnification", @"com.apple.dock") ?: NSNull.null,
    @"dockTileSize": PrefApp(@"tilesize", @"com.apple.dock") ?: NSNull.null,
    @"dockLargeSize": PrefApp(@"largesize", @"com.apple.dock") ?: NSNull.null,
    @"dockAutohide": PrefApp(@"autohide", @"com.apple.dock") ?: NSNull.null,
    @"naturalScrolling": PrefAny(@"com.apple.swipescrolldirection", nil) ?: NSNull.null,
    @"AppleAccentColor": PrefAny(@"AppleAccentColor", nil) ?: NSNull.null,
    @"AppleHighlightColor": PrefAny(@"AppleHighlightColor", nil) ?: NSNull.null,
  });
}

// ---- S3 ----
static NSDictionary *AlphaProbe(uint32_t wid, NSString *label) {
  int owner = 0;
  CGError ownErr = SLS.GetWindowOwner ? SLS.GetWindowOwner(gCID, wid, &owner) : -1;
  float before = -1, after = -1, restored = -1;
  CGError g0 = SLS.GetWindowAlpha ? SLS.GetWindowAlpha(gCID, wid, &before) : -1;
  CGError setErr = SLS.SetWindowAlpha(gCID, wid, 0.5f);
  SpikePump(0.3);
  CGError g1 = SLS.GetWindowAlpha ? SLS.GetWindowAlpha(gCID, wid, &after) : -1;
  CGError resetErr = SLS.SetWindowAlpha(gCID, wid, before >= 0 ? before : 1.0f);
  SpikePump(0.2);
  if (SLS.GetWindowAlpha) SLS.GetWindowAlpha(gCID, wid, &restored);
  return @{@"target": label, @"wid": @(wid), @"ownerCID": @(owner), @"ourCID": @(gCID), @"getOwnerErr": @(ownErr),
           @"alphaBefore": @(before), @"getErr": @(g0), @"setAlpha0_5Err": @(setErr), @"alphaAfterSet": @(after),
           @"getErrAfter": @(g1), @"restoreErr": @(resetErr), @"alphaRestored": @(restored),
           @"mutated": @(after >= 0 && fabsf(after - 0.5f) < 0.01f)};
}

NSTask *SpikeSpawnHelper(NSString *mode, NSArray *extra, NSString **lineOut) {
  NSTask *t = [NSTask new];
  t.executableURL = NSBundle.mainBundle.executableURL;
  t.arguments = [@[mode, @"--evidence", gEvidenceDir] arrayByAddingObjectsFromArray:extra ?: @[]];
  NSPipe *pipe = [NSPipe pipe];
  t.standardOutput = pipe;
  if (![t launchAndReturnError:nil]) return nil;
  NSMutableData *buf = [NSMutableData data];
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
  while ([limit timeIntervalSinceNow] > 0) {
    NSData *d = pipe.fileHandleForReading.availableData;  // blocks until data or EOF
    if (!d.length) break;
    [buf appendData:d];
    NSString *s = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
    NSRange nl = [s rangeOfString:@"\n"];
    if (nl.location != NSNotFound) { if (lineOut) *lineOut = [s substringToIndex:nl.location]; break; }
  }
  return t;
}

static NSTask *SpawnHelper(NSString *mode, uint32_t *widOut, pid_t *pidOut) {
  NSString *line = nil;
  NSTask *t = SpikeSpawnHelper(mode, nil, &line);
  unsigned w = 0; int p = 0;
  if (line) sscanf(line.UTF8String, "wid=%u pid=%d", &w, &p);
  *widOut = w; *pidOut = p;
  return t;
}

void TestS3(NSDictionary *a, SpikeDone done) {
  if (!SLS.SetWindowAlpha) { done(@{@"status": @"FAIL", @"why": @"SLSSetWindowAlpha missing"}); return; }
  NSMutableArray *probes = [NSMutableArray array];
  NSWindow *own = SpikeMakeWindow(NSMakeRect(80, 80, 320, 200), NSColor.systemGrayColor, @"FDS S3 own", YES);
  SpikePump(0.4);
  [probes addObject:AlphaProbe(SpikeWID(own), @"own window (same connection)")];
  [own close];

  uint32_t hwid = 0; pid_t hpid = 0;
  NSTask *helper = SpawnHelper(@"helper-window", &hwid, &hpid);
  if (hwid) [probes addObject:AlphaProbe(hwid, @"spike helper process window (second process we own)")];
  [helper terminate];

  pid_t te = SpikeOpenScratchTextEdit(@"s3-scratch.txt", @"FocusDock spike S3 scratch document.\n", 15);
  uint32_t twid = 0;
  for (NSDictionary *w in SpikeWindowsOfPID(te))
    if ([w[(id)kCGWindowLayer] intValue] == 0 && [w[(id)kCGWindowBounds][@"Height"] doubleValue] > 100) { twid = [w[(id)kCGWindowNumber] unsignedIntValue]; break; }
  if (twid) [probes addObject:AlphaProbe(twid, @"TextEdit scratch instance window (foreign app)")];
  SpikeQuitApp(te);

  BOOL ownOK = [probes[0][@"mutated"] boolValue];
  BOOL anyForeignMutated = NO;
  for (NSUInteger i = 1; i < probes.count; i++) anyForeignMutated |= [probes[i][@"mutated"] boolValue];
  done(@{@"status": (probes.count == 3 && ownOK) ? @"PASS" : @"PARTIAL", @"probes": probes,
         @"foreignMutationAllowed": @(anyForeignMutated),
         @"note": @"PASS means the gate was measured (own window mutable, foreign result recorded), not that foreign mutation works"});
}

void HelperWindow(NSDictionary *a, SpikeDone done) {
  NSWindow *w = SpikeMakeWindow(NSMakeRect(420, 120, 300, 200), NSColor.systemTealColor, @"FDS helper", YES);
  SpikePump(0.3);
  printf("wid=%u pid=%d\n", SpikeWID(w), getpid());
  fflush(stdout);
  (void)done;  // runs until the parent terminates it or the harness timeout fires
}

// Holds Secure Event Input while frontmost, exactly what Terminal's Secure Keyboard Entry does.
void HelperSecureInput(NSDictionary *a, SpikeDone done) {
  NSWindow *w = SpikeMakeWindow(NSMakeRect(420, 360, 360, 120), NSColor.systemOrangeColor, @"FDS secure input", YES);
  NSTextField *f = [NSSecureTextField textFieldWithString:@""];
  f.frame = NSMakeRect(20, 40, 320, 24);
  [w.contentView addSubview:f];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp activateIgnoringOtherApps:YES];
  [w makeKeyAndOrderFront:nil];
  [w makeFirstResponder:f];
  OSStatus st = EnableSecureEventInput();
  SpikeAddCleanup(^{ DisableSecureEventInput(); });
  SpikePump(0.3);
  printf("wid=%u pid=%d enable=%d secure=%d\n", SpikeWID(w), getpid(), (int)st, (int)IsSecureEventInputEnabled());
  fflush(stdout);
  double hold = a[@"hold"] ? [a[@"hold"] doubleValue] : 8;
  SpikeAfter(hold, ^{ done(@{}); });
}

// ---- S13 ----
void TestS13(NSDictionary *a, SpikeDone done) {
  NSDictionary *perm = SpikePermissions();
  if (![perm[@"fullDiskAccess"] boolValue]) {
    done(SpikeBlocked(@"S13", [NSString stringWithFormat:@"usernoted db open() errno %@", perm[@"usernotedDBOpenErrno"]], @[@"Full Disk Access"]));
    return;
  }
  NSString *src = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Group Containers/group.com.apple.usernoted/db2"];
  NSString *dst = [gEvidenceDir stringByAppendingPathComponent:@"scratch/usernoted"];
  NSFileManager *fm = NSFileManager.defaultManager;
  [fm removeItemAtPath:dst error:nil];
  [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
  NSMutableDictionary *copied = [NSMutableDictionary dictionary];
  for (NSString *n in @[@"db", @"db-wal", @"db-shm"]) {
    NSError *err = nil;
    NSString *from = [src stringByAppendingPathComponent:n];
    // Read-only copy: NSData read + write elsewhere, never open the original for writing.
    NSData *d = [NSData dataWithContentsOfFile:from options:0 error:&err];
    if (d) [d writeToFile:[dst stringByAppendingPathComponent:n] atomically:YES];
    copied[n] = d ? @(d.length) : (err.localizedDescription ?: @"missing");
  }
  NSArray *listing = [fm contentsOfDirectoryAtPath:src error:nil] ?: @[];
  // Control: an FDA-protected path; open() is closed at once, nothing is read.
  NSMutableDictionary *control = [NSMutableDictionary dictionary];
  for (NSString *rel in @[@"Library/Safari/History.db", @"Library/Mail", @"Library/Messages/chat.db"]) {
    int fd = open([NSHomeDirectory() stringByAppendingPathComponent:rel].fileSystemRepresentation, O_RDONLY);
    control[rel] = fd >= 0 ? @"opened" : @(errno);
    if (fd >= 0) close(fd);
  }
  done(@{@"status": copied[@"db"] && [copied[@"db"] isKindOfClass:NSNumber.class] ? @"PASS" : @"FAIL",
         @"copied": copied, @"dbDirListing": listing, @"fdaControlOpen": control, @"copyDir": dst});
}

// ---- notification permission (shows the system prompt; run only when the user is ready) ----
void TestNotifyAuth(NSDictionary *a, SpikeDone done) {
  [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                                                                    completionHandler:^(BOOL granted, NSError *err) {
    SpikeOnMain(^{
      done(@{@"test": @"notify-auth", @"status": granted ? @"PASS" : @"BLOCKED", @"granted": @(granted), @"error": err.description ?: @""});
    });
  }];
}

void TestNotifyStatus(NSDictionary *a, SpikeDone done) {
  [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *st) {
    SpikeOnMain(^{
      done(@{@"test": @"notify-status", @"status": @"INFO", @"authorizationStatus": @(st.authorizationStatus),
             @"alertSetting": @(st.alertSetting), @"alertStyle": @(st.alertStyle)});
    });
  }];
}

// Shows the system Accessibility and Screen Recording prompts for this app (the user answers them).
void TestRequestPerms(NSDictionary *a, SpikeDone done) {
  BOOL ax = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES});
  BOOL sr = CGRequestScreenCaptureAccess();
  done(@{@"test": @"request-perms", @"status": @"INFO", @"accessibilityNow": @(ax), @"screenRecordingNow": @(sr)});
}

// Real Screen Recording check: preflight can lag a fresh grant, SCShareableContent cannot lie.
void TestSCKProbe(NSDictionary *a, SpikeDone done) {
  BOOL pre = CGPreflightScreenCaptureAccess();
  [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *c, NSError *e) {
    SpikeOnMain(^{
      done(@{@"test": @"sck-probe", @"status": @"INFO", @"preflight": @(pre), @"sckError": e ? [NSString stringWithFormat:@"%@ %ld", e.domain, (long)e.code] : @"",
             @"displays": @(c.displays.count), @"windows": @(c.windows.count)});
    });
  }];
}
