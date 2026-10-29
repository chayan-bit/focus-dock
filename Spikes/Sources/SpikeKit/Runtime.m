// Harness: argument parsing, JSON result log, SPI resolution and shared helpers.
#import "Spike.h"
#import "SpikeKit.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/nlist.h>
#import <objc/runtime.h>

SLSApi SLS;
int gCID;
NSString *gEvidenceDir;
static NSString *gOutPath;
static NSMutableArray<dispatch_block_t> *gCleanups;

void SpikeAddCleanup(dispatch_block_t block) {
  if (!gCleanups) gCleanups = [NSMutableArray array];
  [gCleanups addObject:block];
}

static void RunCleanups(void) {
  while (gCleanups.count) {
    dispatch_block_t b = gCleanups.lastObject;
    [gCleanups removeLastObject];
    b();
  }
}

void SpikeLog(NSString *fmt, ...) {
  va_list ap; va_start(ap, fmt);
  NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
  va_end(ap);
  fprintf(stderr, "[spike %.3f] %s\n", CACurrentMediaTime(), s.UTF8String);
}

// Main-thread scheduling through the run loop, not the GCD main queue: tests wait by nesting the
// run loop, and the main queue does not drain re-entrantly, so GCD-main callbacks would stall.
void SpikeOnMain(dispatch_block_t block) {
  CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, block);
  CFRunLoopWakeUp(CFRunLoopGetMain());
}

void SpikeAfter(double seconds, dispatch_block_t block) {
  NSTimer *t = [NSTimer timerWithTimeInterval:seconds repeats:NO block:^(NSTimer *x) { block(); }];
  [NSRunLoop.mainRunLoop addTimer:t forMode:NSRunLoopCommonModes];
}

NSDictionary *SpikeBlocked(NSString *test, NSString *why, NSArray *needs) {
  return @{@"test": test, @"status": @"BLOCKED", @"why": why, @"needs": needs ?: @[]};
}

// Same in-memory symtab walk as tools/rea/probe.m (yabai does the same for this local symbol).
static void *findLocal(const char *img, const char *sym) {
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    if (strcmp(_dyld_get_image_name(i), img)) continue;
    const struct mach_header_64 *h = (const void *)_dyld_get_image_header(i);
    intptr_t slide = _dyld_get_image_vmaddr_slide(i);
    const struct load_command *lc = (const void *)(h + 1);
    const struct segment_command_64 *le = 0; const struct symtab_command *st = 0;
    for (uint32_t c = 0; c < h->ncmds; c++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
      if (lc->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)lc)->segname, "__LINKEDIT")) le = (const void *)lc;
      if (lc->cmd == LC_SYMTAB) st = (const void *)lc;
    }
    if (!le || !st) return NULL;
    uintptr_t base = le->vmaddr + slide - le->fileoff;
    const struct nlist_64 *nl = (const void *)(base + st->symoff);
    const char *strs = (const void *)(base + st->stroff);
    for (uint32_t k = 0; k < st->nsyms; k++)
      if (!strcmp(strs + nl[k].n_un.n_strx, sym)) return (void *)(nl[k].n_value + slide);
  }
  return NULL;
}

void SpikeResolveSPI(NSMutableDictionary *report) {
  void *sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
  void *hi = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_NOW);
  NSMutableArray *missing = [NSMutableArray array];
#define R(field, name) do { SLS.field = dlsym(sl, name); if (!SLS.field) SLS.field = dlsym(RTLD_DEFAULT, name); if (!SLS.field) [missing addObject:@name]; } while (0)
  R(MainConnectionID, "SLSMainConnectionID");
  R(SetWindowAlpha, "SLSSetWindowAlpha");
  R(GetWindowAlpha, "SLSGetWindowAlpha");
  R(CopySpacesForWindows, "SLSCopySpacesForWindows");
  R(CopyManagedDisplaySpaces, "SLSCopyManagedDisplaySpaces");
  R(GetActiveSpace, "SLSGetActiveSpace");
  R(SpaceGetType, "SLSSpaceGetType");
  R(MoveWindowsToManagedSpace, "SLSMoveWindowsToManagedSpace");
  R(GetWindowOwner, "SLSGetWindowOwner");
  R(ConnectionGetPID, "SLSConnectionGetPID");
  R(GetMenuBarAutohideEnabled, "CGSGetMenuBarAutohideEnabled");
  R(IsSecureEventInputSet, "CGSIsSecureEventInputSet");
  R(IsSymbolicHotKeyEnabled, "CGSIsSymbolicHotKeyEnabled");
  R(GetProcessMenuBarWindowList, "CGSGetProcessMenuBarWindowList");
  R(GetOnScreenWindowCount, "CGSGetOnScreenWindowCount");
#undef R
  SLS.CoreDockSendNotification = hi ? dlsym(hi, "CoreDockSendNotification") : NULL;
  if (!SLS.CoreDockSendNotification) SLS.CoreDockSendNotification = dlsym(RTLD_DEFAULT, "CoreDockSendNotification");
  if (!SLS.CoreDockSendNotification) [missing addObject:@"CoreDockSendNotification"];
  SLS.PerformAsyncBridgedOp = findLocal("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
      "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
  if (!SLS.PerformAsyncBridgedOp) [missing addObject:@"SLSPerformAsynchronousBridgedWindowManagementOperation(local)"];
  gCID = SLS.MainConnectionID ? SLS.MainConnectionID() : 0;
  report[@"spiMissing"] = missing;
}

NSWindow *SpikeMakeWindow(NSRect frame, NSColor *color, NSString *title, BOOL titled) {
  NSWindowStyleMask mask = titled ? (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable) : NSWindowStyleMaskBorderless;
  NSWindow *w = [[NSWindow alloc] initWithContentRect:frame styleMask:mask backing:NSBackingStoreBuffered defer:NO];
  w.releasedWhenClosed = NO;
  w.title = title ?: @"FocusDock spike";
  w.backgroundColor = color ?: NSColor.windowBackgroundColor;
  w.opaque = YES;
  w.hasShadow = titled;
  // Pin the window to sRGB so the marker colour survives colour management in captures.
  w.colorSpace = NSColorSpace.sRGBColorSpace;
  [w orderFrontRegardless];
  return w;
}

uint32_t SpikeWID(NSWindow *w) { return (uint32_t)w.windowNumber; }

NSArray<NSNumber *> *SpikeSpacesForWindow(uint32_t wid) {
  if (!SLS.CopySpacesForWindows) return @[];
  CFArrayRef r = SLS.CopySpacesForWindows(gCID, 0x7, (__bridge CFArrayRef)@[@(wid)]);
  return r ? CFBridgingRelease(r) : @[];
}

NSArray<NSDictionary *> *SpikeUserSpaces(void) {
  NSMutableArray *out = [NSMutableArray array];
  if (!SLS.CopyManagedDisplaySpaces) return out;
  NSArray *displays = CFBridgingRelease(SLS.CopyManagedDisplaySpaces(gCID));
  for (NSDictionary *d in displays) {
    NSInteger idx = 0;
    for (NSDictionary *s in d[@"Spaces"]) {
      [out addObject:@{@"id": s[@"id64"] ?: s[@"ManagedSpaceID"] ?: @0, @"type": s[@"type"] ?: @-1,
                       @"display": d[@"Display Identifier"] ?: @"", @"index": @(++idx)}];
    }
  }
  return out;
}

NSDictionary *SpikeWindowInfo(uint32_t wid) {
  NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, wid));
  return list.firstObject ?: @{};
}

NSArray<NSDictionary *> *SpikeWindowsOfPID(pid_t pid) {
  NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
  NSMutableArray *out = [NSMutableArray array];
  for (NSDictionary *w in list)
    if ([w[(id)kCGWindowOwnerPID] intValue] == pid) [out addObject:w];
  return out;
}

static NSString *ScratchDir(void) {
  NSString *d = [gEvidenceDir stringByAppendingPathComponent:@"scratch"];
  [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
  return d;
}

// Launches a NEW TextEdit instance on a scratch file we wrote; never touches a TextEdit the user runs.
pid_t SpikeOpenScratchTextEdit(NSString *name, NSString *contents, double timeout) {
  NSString *path = [ScratchDir() stringByAppendingPathComponent:name];
  [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
  NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
  cfg.createsNewApplicationInstance = YES;
  cfg.arguments = @[@"-ApplePersistenceIgnoreState", @"YES"];
  cfg.activates = YES;
  __block pid_t pid = 0;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:path]] withApplicationAtURL:app configuration:cfg
                      completionHandler:^(NSRunningApplication *ra, NSError *err) {
    pid = ra.processIdentifier;
    if (err) SpikeLog(@"TextEdit open error %@", err);
    dispatch_semaphore_signal(sem);
  }];
  // Spin the main run loop while waiting (we are called on the main thread).
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) && [limit timeIntervalSinceNow] > 0)
    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  // Wait for its document window to exist.
  while (pid && [limit timeIntervalSinceNow] > 0) {
    for (NSDictionary *w in SpikeWindowsOfPID(pid))
      if ([w[(id)kCGWindowLayer] intValue] == 0 && [w[(id)kCGWindowBounds][@"Height"] doubleValue] > 100) return pid;
    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  }
  return pid;
}

uint32_t SpikeMainWindowOfPID(pid_t pid) {
  uint32_t best = 0; double area = 0;
  for (NSDictionary *w in SpikeWindowsOfPID(pid)) {
    if ([w[(id)kCGWindowLayer] intValue] != 0) continue;
    double a = [w[(id)kCGWindowBounds][@"Width"] doubleValue] * [w[(id)kCGWindowBounds][@"Height"] doubleValue];
    if (a > area) { area = a; best = [w[(id)kCGWindowNumber] unsignedIntValue]; }
  }
  return area > 100 * 100 ? best : 0;
}

// Waits while dispatching NSEvents (Carbon hotkeys, AppKit) and run-loop sources.
void SpikePump(double seconds) {
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow] > 0) {
    NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.01, MAX(0, [end timeIntervalSinceNow]))]
                                       inMode:NSDefaultRunLoopMode dequeue:YES];
    if (e) [NSApp sendEvent:e];
  }
}

void SpikeQuitApp(pid_t pid) {
  NSRunningApplication *ra = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
  if (!ra) return;
  [ra terminate];
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
  while (!ra.terminated && [limit timeIntervalSinceNow] > 0)
    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  if (!ra.terminated) [ra forceTerminate];  // our own scratch instance only
}

NSDictionary *SpikePermissions(void) {
  NSString *db = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Group Containers/group.com.apple.usernoted/db2/db"];
  int fd = open(db.fileSystemRepresentation, O_RDONLY);
  int fdaErr = fd < 0 ? errno : 0;
  if (fd >= 0) close(fd);
  return @{
    @"accessibility": @(AXIsProcessTrusted()),
    @"screenRecording": @(CGPreflightScreenCaptureAccess()),
    @"postEvent": @(CGPreflightPostEventAccess()),
    @"listenEvent": @(CGPreflightListenEventAccess()),
    @"fullDiskAccess": @(fd >= 0 || fdaErr == ENOENT),
    @"usernotedDBOpenErrno": @(fdaErr),
  };
}

BOOL SpikeWritePNG(CGImageRef img, NSString *path, double scale) {
  if (!img) return NO;
  CGImageRef out = img;
  CGContextRef ctx = NULL;
  if (scale != 1.0) {
    size_t w = MAX(1, (size_t)(CGImageGetWidth(img) * scale)), h = MAX(1, (size_t)(CGImageGetHeight(img) * scale));
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    out = CGBitmapContextCreateImage(ctx);
  }
  CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                              (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
  CGImageDestinationAddImage(dst, out, NULL);
  BOOL ok = CGImageDestinationFinalize(dst);
  CFRelease(dst);
  if (ctx) { CGImageRelease(out); CGContextRelease(ctx); }
  return ok;
}

// ---- entry ----
typedef struct { const char *name; SpikeTest fn; double timeout; } Entry;
static const Entry kTests[] = {
  {"env", TestEnv, 20}, {"S1", TestS1, 60}, {"S2", TestS2, 180}, {"S3", TestS3, 60},
  {"S4", TestS4, 60}, {"S5", TestS5, 60}, {"S6", TestS6, 180}, {"S7", TestS7, 180},
  {"S8", TestS8, 60}, {"S9", TestS9, 60}, {"S10", TestS10, 120}, {"S12", TestS12, 90},
  {"S13", TestS13, 60}, {"notify-auth", TestNotifyAuth, 120}, {"notify-status", TestNotifyStatus, 20}, {"request-perms", TestRequestPerms, 30}, {"sck-probe", TestSCKProbe, 30},
  {"helper-window", HelperWindow, 600}, {"helper-secure-input", HelperSecureInput, 600},
};

static void Emit(NSDictionary *result) {
  NSMutableDictionary *r = [result mutableCopy];
  r[@"at"] = [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
  NSData *json = [NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingSortedKeys error:nil];
  NSMutableData *line = [json mutableCopy];
  [line appendBytes:"\n" length:1];
  fwrite(line.bytes, 1, line.length, stdout);
  fflush(stdout);
  if (gOutPath) {
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gOutPath];
    if (!fh) { [NSFileManager.defaultManager createFileAtPath:gOutPath contents:nil attributes:nil]; fh = [NSFileHandle fileHandleForWritingAtPath:gOutPath]; }
    [fh seekToEndOfFile]; [fh writeData:line]; [fh closeFile];
  }
}

int spike_main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) { fprintf(stderr, "usage: FocusDockSpike <test> [--out file] [--evidence dir] [key=value...]\n"); return 64; }
    NSString *name = @(argv[1]);
    NSMutableDictionary *args = [NSMutableDictionary dictionary];
    for (int i = 2; i < argc; i++) {
      NSString *a = @(argv[i]);
      if ([a isEqualToString:@"--out"] && i + 1 < argc) { gOutPath = @(argv[++i]); continue; }
      if ([a isEqualToString:@"--evidence"] && i + 1 < argc) { gEvidenceDir = @(argv[++i]); continue; }
      NSRange eq = [a rangeOfString:@"="];
      if (eq.location != NSNotFound) args[[a substringToIndex:eq.location]] = [a substringFromIndex:eq.location + 1];
    }
    if (!gEvidenceDir) gEvidenceDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"FocusDockSpike"];
    [NSFileManager.defaultManager createDirectoryAtPath:gEvidenceDir withIntermediateDirectories:YES attributes:nil error:nil];

    const Entry *entry = NULL;
    for (size_t i = 0; i < sizeof(kTests) / sizeof(kTests[0]); i++)
      if (!strcmp(kTests[i].name, argv[1])) entry = &kTests[i];
    if (!entry) { fprintf(stderr, "unknown test %s\n", argv[1]); return 64; }

    NSMutableDictionary *spi = [NSMutableDictionary dictionary];
    SpikeResolveSPI(spi);
    [NSApplication sharedApplication];
    BOOL helper = [name hasPrefix:@"helper-"];
    BOOL quiet = helper || [@[@"env", @"notify-status", @"sck-probe"] containsObject:name];  // never steal focus while polling
    [NSApp setActivationPolicy:quiet ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular];
    __block BOOL finished = NO;
    SpikeDone done = ^(NSDictionary *result) {
      if (finished) return;
      finished = YES;
      RunCleanups();
      NSMutableDictionary *r = [result mutableCopy];
      if (!r[@"test"]) r[@"test"] = name;
      if ([spi[@"spiMissing"] count]) r[@"spiMissing"] = spi[@"spiMissing"];
      if (!helper) Emit(r);
      [NSApp terminate:nil];
    };
    SpikeOnMain(^{
      SpikeLog(@"start %@ args=%@", name, args);
      entry->fn(args, done);
    });
    double timeout = args[@"timeout"] ? [args[@"timeout"] doubleValue] : entry->timeout;
    SpikeAfter(timeout, ^{ done(@{@"test": name, @"status": @"FAIL", @"why": @"harness timeout"}); });
    [NSApp run];
  }
  return 0;
}
