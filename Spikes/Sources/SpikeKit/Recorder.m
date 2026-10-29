// ScreenCaptureKit display recorder that reduces each frame to the bounding box of a solid
// marker colour, so motion curves can be fitted without storing video.
#import "Spike.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

@interface SpikeRecorder () <SCStreamOutput, SCStreamDelegate>
@property(nonatomic, strong) SCStream *stream;
@property(nonatomic, strong) dispatch_queue_t queue;
@end

@implementation SpikeRecorder

- (instancetype)init {
  if ((self = [super init])) {
    _samples = [NSMutableArray array];
    _queue = dispatch_queue_create("spike.recorder", DISPATCH_QUEUE_SERIAL);
    _markerR = 255; _markerG = 0; _markerB = 255;
  }
  return self;
}

- (void)startOnMainDisplayFPS:(int)fps completion:(void (^)(NSError *))completion {
  [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES
                                               completionHandler:^(SCShareableContent *content, NSError *err) {
    if (err || !content.displays.count) { SpikeOnMain(^{ completion(err ?: [NSError errorWithDomain:@"spike" code:1 userInfo:nil]); }); return; }
    SCDisplay *display = content.displays.firstObject;
    for (SCDisplay *d in content.displays) if (d.displayID == CGMainDisplayID()) display = d;
    SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
    SCStreamConfiguration *cfg = [SCStreamConfiguration new];
    cfg.width = display.width;   // points: 1 px per point keeps per-frame scanning cheap
    cfg.height = display.height;
    cfg.minimumFrameInterval = CMTimeMake(1, fps);
    cfg.pixelFormat = kCVPixelFormatType_32BGRA;
    cfg.colorSpaceName = kCGColorSpaceSRGB;
    cfg.showsCursor = NO;
    cfg.queueDepth = 8;
    self.stream = [[SCStream alloc] initWithFilter:filter configuration:cfg delegate:self];
    NSError *addErr = nil;
    [self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self.queue error:&addErr];
    if (addErr) { SpikeOnMain(^{ completion(addErr); }); return; }
    [self.stream startCaptureWithCompletionHandler:^(NSError *e) { SpikeOnMain(^{ completion(e); }); }];
  }];
}

- (void)stop:(void (^)(void))completion {
  [self.stream stopCaptureWithCompletionHandler:^(NSError *e) {
    dispatch_sync(self.queue, ^{});  // drain in-flight frames
    SpikeOnMain(completion);
  }];
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error { SpikeLog(@"recorder stopped: %@", error); }

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sb ofType:(SCStreamOutputType)type {
  if (type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sb)) return;
  CFArrayRef atts = CMSampleBufferGetSampleAttachmentsArray(sb, false);
  if (atts && CFArrayGetCount(atts)) {
    NSDictionary *a = (__bridge NSDictionary *)CFArrayGetValueAtIndex(atts, 0);
    if ([a[SCStreamFrameInfoStatus] integerValue] != SCFrameStatusComplete) return;
  }
  CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
  if (!pb) return;
  double t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb));
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  const uint8_t *base = CVPixelBufferGetBaseAddress(pb);
  size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb);
  NSInteger idx = self.framesSeen++;
  if (self.saveFramesPrefix && self.saveEvery > 0 && idx % self.saveEvery == 0) {
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate((void *)base, w, h, 8, row, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    SpikeWritePNG(img, [NSString stringWithFormat:@"%@-%04ld.png", self.saveFramesPrefix, (long)idx], 0.25);
    CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
  }
  if (self.analyzer) {
    NSDictionary *r = self.analyzer(base, w, h, row, t);
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    if (r) @synchronized(self.samples) { [self.samples addObject:r]; }
    return;
  }
  long x0 = LONG_MAX, x1 = -1, y0 = LONG_MAX, y1 = -1, n = 0;
  const int tol = 40;
  for (size_t y = 0; y < h; y += 2) {
    const uint8_t *p = base + y * row;
    for (size_t x = 0; x < w; x += 2) {
      const uint8_t *px = p + x * 4;  // B G R A
      if (abs(px[2] - _markerR) < tol && abs(px[1] - _markerG) < tol && abs(px[0] - _markerB) < tol) {
        n++;
        if ((long)x < x0) x0 = x;
        if ((long)x > x1) x1 = x;
        if ((long)y < y0) y0 = y;
        if ((long)y > y1) y1 = y;
      }
    }
  }
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  NSDictionary *s = n ? @{@"t": @(t), @"x0": @(x0), @"x1": @(x1), @"y0": @(y0), @"y1": @(y1), @"n": @(n)}
                      : @{@"t": @(t), @"n": @0};
  @synchronized(self.samples) { [self.samples addObject:s]; }
}

@end
