// Z3View.m
#import "Z3View.h"
#include "Z3Runtime.h"

// Release-callback context for a zero-copy CGDataProvider. One of these is
// allocated per CGImage; freed in the callback once Core Animation is truly
// done reading the pixels (which may be well after -tick: returns, since
// CALayer.contents compositing happens on the render server).
typedef struct { int handle; } FrameToken;

static void ReleaseFrameCallback(void *info, const void *data, size_t size) {
  (void)data; (void)size;
  FrameToken *tok = (FrameToken *)info;
  Z3Runtime_ReleaseFrame(tok->handle);
  free(tok);
}

@implementation Z3View {
  CALayer *_frameLayer;
  CADisplayLink *_displayLink;
  uint32_t _lastSerial;
  int _gameW, _gameH;   // last frame's logical size, for letterboxing
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [UIColor blackColor];

    NSDictionary *noAnim = @{ @"contents": [NSNull null], @"bounds": [NSNull null],
                              @"position": [NSNull null] };
    _frameLayer = [CALayer layer];
    _frameLayer.opaque = YES;
    _frameLayer.actions = noAnim;
    // Nearest-neighbor: this is a pixel-art SNES framebuffer: linear filtering
    // would blur it at the integer-ish scale factors a phone screen gives.
    _frameLayer.magnificationFilter = kCAFilterNearest;
    _frameLayer.minificationFilter = kCAFilterNearest;
    [self.layer addSublayer:_frameLayer];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self relayoutFrameLayer];
}

- (void)relayoutFrameLayer {
  if (_gameW <= 0 || _gameH <= 0) { _frameLayer.frame = self.bounds; return; }
  CGRect b = self.bounds;
  CGFloat viewAspect = b.size.width / b.size.height;
  CGFloat gameAspect = (CGFloat)_gameW / (CGFloat)_gameH;
  CGRect f;
  if (viewAspect > gameAspect) {
    f.size.height = b.size.height;
    f.size.width = b.size.height * gameAspect;
  } else {
    f.size.width = b.size.width;
    f.size.height = b.size.width / gameAspect;
  }
  f.origin.x = b.origin.x + (b.size.width - f.size.width) * 0.5;
  f.origin.y = b.origin.y + (b.size.height - f.size.height) * 0.5;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _frameLayer.frame = f;
  [CATransaction commit];
}

- (void)start {
  [self stop];
  _lastSerial = 0;
  _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  // iOS 9.3 has no preferredFramesPerSecond throttling worth using here: the
  // game thread already paces itself to 60fps: fire every vsync and let
  // Z3Runtime_AcquireFrame's serial check make repeated calls a no-op.
  [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
  [_displayLink invalidate];
  _displayLink = nil;
}

- (void)tick:(CADisplayLink *)link {
  (void)link;
  Z3Frame f;
  if (!Z3Runtime_AcquireFrame(_lastSerial, &f)) return;
  _lastSerial = f.serial;

  if (f.width != _gameW || f.height != _gameH) {
    _gameW = f.width; _gameH = f.height;
    [self relayoutFrameLayer];
  }

  FrameToken *tok = malloc(sizeof(FrameToken));
  tok->handle = f.handle;
  CGDataProviderRef provider = CGDataProviderCreateWithData(
      tok, f.pixels, f.pitch * (size_t)f.height, ReleaseFrameCallback);
  if (!provider) {
    // Creation failed before taking ownership of tok/the buffer: release both now.
    free(tok);
    Z3Runtime_ReleaseFrame(f.handle);
    return;
  }

  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  // Matches Z3Runtime's ARGB8888-in-memory-as-BGRA-little-endian layout (see
  // Z3Frame doc comment): opaque, byte order 32 little, alpha-none-skip-first.
  CGImageRef img = CGImageCreate((size_t)f.width, (size_t)f.height, 8, 32, f.pitch,
      cs, (CGBitmapInfo)(kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little),
      provider, NULL, false, kCGRenderingIntentDefault);
  CGColorSpaceRelease(cs);
  CGDataProviderRelease(provider);  // CGImage retains it; this drops our ref

  if (img) {
    _frameLayer.contents = (__bridge id)img;
    CGImageRelease(img);
  } else {
    // CGImageCreate failed to take a reference on the provider. We already
    // dropped ours with CGDataProviderRelease() above, so its refcount just
    // hit 0 and ReleaseFrameCallback already ran synchronously -- tok is freed
    // and the buffer returned to Z3Runtime. Nothing left to do here.
  }
}

- (CGPoint)viewPointToGameUnit:(CGPoint)pt {
  CGRect f = _frameLayer.frame;
  if (f.size.width <= 0 || f.size.height <= 0) return CGPointMake(-1, -1);
  CGFloat ux = (pt.x - f.origin.x) / f.size.width;
  CGFloat uy = (pt.y - f.origin.y) / f.size.height;
  return CGPointMake(ux, uy);
}

@end
