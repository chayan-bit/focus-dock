#pragma once
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

// ---- SkyLight / CoreGraphics SPI, resolved with dlsym (rea-macos-ui.md tags them SPI) ----
typedef int CGSConnectionID;
typedef struct {
  int (*MainConnectionID)(void);
  CGError (*SetWindowAlpha)(int cid, uint32_t wid, float alpha);
  CGError (*GetWindowAlpha)(int cid, uint32_t wid, float *alpha);
  CFArrayRef (*CopySpacesForWindows)(int cid, int mask, CFArrayRef wids);
  CFArrayRef (*CopyManagedDisplaySpaces)(int cid);
  uint64_t (*GetActiveSpace)(int cid);
  int (*SpaceGetType)(int cid, uint64_t sid);
  void (*MoveWindowsToManagedSpace)(int cid, CFArrayRef wids, uint64_t sid);
  CGError (*GetWindowOwner)(int cid, uint32_t wid, int *owner);
  CGError (*ConnectionGetPID)(int cid, pid_t *pid);
  CGError (*GetMenuBarAutohideEnabled)(int cid, bool *enabled);
  bool (*IsSecureEventInputSet)(void);
  bool (*IsSymbolicHotKeyEnabled)(int hotkey);
  CGError (*GetProcessMenuBarWindowList)(int cid, int target, int count, uint32_t *list, int *outCount);
  CGError (*GetOnScreenWindowCount)(int cid, int target, int *outCount);
  void (*CoreDockSendNotification)(CFStringRef note, int unknown);
  void (*PerformAsyncBridgedOp)(id op);  // local symbol, found via the in-memory symtab
} SLSApi;
extern SLSApi SLS;
extern int gCID;
void SpikeResolveSPI(NSMutableDictionary *report);

// ---- harness ----
typedef void (^SpikeDone)(NSDictionary *result);
typedef void (*SpikeTest)(NSDictionary *args, SpikeDone done);
extern NSString *gEvidenceDir;  // per-run evidence output directory
void SpikeLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
NSDictionary *SpikeBlocked(NSString *test, NSString *why, NSArray *needs);
void SpikeAfter(double seconds, dispatch_block_t block);
void SpikeOnMain(dispatch_block_t block);
// Restore steps run (LIFO) before the result is written, also on harness timeout.
void SpikeAddCleanup(dispatch_block_t block);

// ---- shared helpers ----
NSWindow *SpikeMakeWindow(NSRect frame, NSColor *color, NSString *title, BOOL titled);
uint32_t SpikeWID(NSWindow *w);
NSArray<NSNumber *> *SpikeSpacesForWindow(uint32_t wid);
NSArray<NSDictionary *> *SpikeUserSpaces(void);  // [{id, type, display}] in Mission Control order
NSDictionary *SpikeWindowInfo(uint32_t wid);
NSArray<NSDictionary *> *SpikeWindowsOfPID(pid_t pid);
pid_t SpikeOpenScratchTextEdit(NSString *name, NSString *contents, double timeout);
void SpikeQuitApp(pid_t pid);
NSDictionary *SpikePermissions(void);
BOOL SpikeWritePNG(CGImageRef img, NSString *path, double scale);
// SCK single-window capture (works for windows on other Spaces too); completion on main.
void SpikeCaptureWindow(uint32_t wid, void (^then)(CGImageRef img, NSDictionary *info));
// 64x64 luma stats; meanAbsDiffVsOther compares against `other` when given.
NSDictionary *SpikeImageStats(CGImageRef img, CGImageRef other);
uint32_t SpikeMainWindowOfPID(pid_t pid);
void SpikePump(double seconds);
// Launches this app again in a helper mode; returns after its first stdout line.
NSTask *SpikeSpawnHelper(NSString *mode, NSArray *extra, NSString **lineOut);

// ---- DockSwipe (ported from InstantSpaceSwitcher, MIT) ----
// phase: 1 began, 2 changed, 4 ended. progress, velocity are signed in the Dock's convention.
bool SpikePostDockSwipe(int phase, double progress, double velocity, bool modern);
double SpikeSwipeSign(int direction);  // direction +1 = next Space (right), -1 = previous

// ---- SCK recorder: tracks a solid marker colour per frame ----
@interface SpikeRecorder : NSObject
@property(nonatomic) uint8_t markerR, markerG, markerB;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *samples;  // {t, x0, x1, y0, y1, n}
@property(nonatomic) NSInteger framesSeen;
@property(nonatomic, copy) NSString *saveFramesPrefix;  // optional: save every k-th frame as PNG
@property(nonatomic) NSInteger saveEvery;
// Optional per-frame reducer (BGRA, 1 px per point) replacing the marker scan; runs off the main thread.
@property(nonatomic, copy) NSDictionary * (^analyzer)(const uint8_t *base, size_t w, size_t h, size_t row, double t);
- (void)startOnMainDisplayFPS:(int)fps completion:(void (^)(NSError *err))completion;
- (void)stop:(void (^)(void))completion;
@end

// ---- tests ----
void TestEnv(NSDictionary *a, SpikeDone d);
void TestS1(NSDictionary *a, SpikeDone d);
void TestS2(NSDictionary *a, SpikeDone d);
void TestS3(NSDictionary *a, SpikeDone d);
void TestS4(NSDictionary *a, SpikeDone d);
void TestS5(NSDictionary *a, SpikeDone d);
void TestS6(NSDictionary *a, SpikeDone d);
void TestS7(NSDictionary *a, SpikeDone d);
void TestS8(NSDictionary *a, SpikeDone d);
void TestS9(NSDictionary *a, SpikeDone d);
void TestS10(NSDictionary *a, SpikeDone d);
void TestS12(NSDictionary *a, SpikeDone d);
void TestS13(NSDictionary *a, SpikeDone d);
void TestNotifyAuth(NSDictionary *a, SpikeDone d);
void TestNotifyStatus(NSDictionary *a, SpikeDone d);
void TestRequestPerms(NSDictionary *a, SpikeDone d);
void TestSCKProbe(NSDictionary *a, SpikeDone d);
void HelperWindow(NSDictionary *a, SpikeDone d);
void HelperSecureInput(NSDictionary *a, SpikeDone d);
