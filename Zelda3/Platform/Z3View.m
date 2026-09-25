// Z3View.m -- GLES2 presentation path.
//
// Pipeline per frame:
//   1. Z3Runtime_AcquireFrame() hands us a HELD buffer (pixels stay valid
//      until we call Z3Runtime_ReleaseFrame()).
//   2. glTexSubImage2D uploads it into a single persistent RGBA8 texture.
//   3. Z3Runtime_ReleaseFrame() -- we've copied the bytes into GPU memory,
//      so the CPU-side buffer can go back to the pool immediately. No
//      release-callback bookkeeping is needed here (unlike the old
//      CGDataProvider path, which had to keep the buffer alive until Core
//      Animation was truly done compositing it, possibly frames later).
//   4. Draw one textured quad, letterboxed to preserve aspect ratio.
//   5. -[EAGLContext presentRenderbuffer:] swaps to screen directly --
//      no CALayer.contents hand-off, no render-server compositing step.
#import "Z3View.h"
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#include "Z3Runtime.h"

@implementation Z3View {
  EAGLContext *_context;
  CADisplayLink *_displayLink;

  GLuint _program;
  GLuint _texture;
  GLuint _vbo;
  GLint _aPosition, _aTexCoord, _uTexture;

  GLuint _framebuffer, _colorRenderbuffer;
  GLint _fbWidth, _fbHeight;

  uint32_t _lastSerial;
  int _gameW, _gameH;      // last uploaded frame's logical size
  int _texW, _texH;        // allocated texture size (>= game size, only grows)
  BOOL _layoutDirty;
}

+ (Class)layerClass { return [CAEAGLLayer class]; }

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [UIColor blackColor];

    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    eaglLayer.opaque = YES;
    eaglLayer.drawableProperties = @{
      kEAGLDrawablePropertyRetainedBacking : @NO,
      kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8
    };
    // Matches the physical pixel grid exactly: this is a nearest-neighbor
    // pixel-art blit, so we want integer-ish sampling, not extra
    // interpolation from an over-scaled drawable.
    self.contentScaleFactor = [UIScreen mainScreen].scale;

    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_context) {
      NSLog(@"Z3View: failed to create GLES2 context");
      return self;
    }
    [self setupGL];
  }
  return self;
}

- (void)dealloc {
  [self stop];
  [self teardownGL];
}

#pragma mark - GL setup

static GLuint CompileShader(GLenum type, const char *src) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, NULL);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[512];
    glGetShaderInfoLog(s, sizeof(log), NULL, log);
    NSLog(@"Z3View: shader compile error: %s", log);
  }
  return s;
}

- (void)setupGL {
  [EAGLContext setCurrentContext:_context];

  static const char *kVertexSrc =
      "attribute vec2 aPosition;\n"
      "attribute vec2 aTexCoord;\n"
      "varying vec2 vTexCoord;\n"
      "void main() {\n"
      "  gl_Position = vec4(aPosition, 0.0, 1.0);\n"
      "  vTexCoord = aTexCoord;\n"
      "}\n";
  static const char *kFragmentSrc =
      "precision mediump float;\n"
      "varying vec2 vTexCoord;\n"
      "uniform sampler2D uTexture;\n"
      "void main() {\n"
      "  gl_FragColor = texture2D(uTexture, vTexCoord);\n"
      "}\n";

  GLuint vs = CompileShader(GL_VERTEX_SHADER, kVertexSrc);
  GLuint fs = CompileShader(GL_FRAGMENT_SHADER, kFragmentSrc);
  _program = glCreateProgram();
  glAttachShader(_program, vs);
  glAttachShader(_program, fs);
  glLinkProgram(_program);
  GLint linked = 0;
  glGetProgramiv(_program, GL_LINK_STATUS, &linked);
  if (!linked) {
    char log[512];
    glGetProgramInfoLog(_program, sizeof(log), NULL, log);
    NSLog(@"Z3View: program link error: %s", log);
  }
  glDeleteShader(vs);
  glDeleteShader(fs);

  _aPosition = glGetAttribLocation(_program, "aPosition");
  _aTexCoord = glGetAttribLocation(_program, "aTexCoord");
  _uTexture = glGetUniformLocation(_program, "uTexture");

  glGenBuffers(1, &_vbo);

  glGenTextures(1, &_texture);
  glBindTexture(GL_TEXTURE_2D, _texture);
  // Nearest-neighbor: this is a pixel-art SNES framebuffer; linear filtering
  // would blur it at the non-integer scale factors a phone/tablet screen gives.
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  glGenFramebuffers(1, &_framebuffer);
  glGenRenderbuffers(1, &_colorRenderbuffer);
}

- (void)teardownGL {
  if (!_context) return;
  [EAGLContext setCurrentContext:_context];
  if (_texture) glDeleteTextures(1, &_texture);
  if (_vbo) glDeleteBuffers(1, &_vbo);
  if (_program) glDeleteProgram(_program);
  if (_colorRenderbuffer) glDeleteRenderbuffers(1, &_colorRenderbuffer);
  if (_framebuffer) glDeleteFramebuffers(1, &_framebuffer);
  [EAGLContext setCurrentContext:nil];
}

// (Re)binds the color renderbuffer to this layer's drawable storage. Must
// run whenever the view's bounds or contentScaleFactor change, and once
// before the first frame.
- (void)updateDrawable {
  [EAGLContext setCurrentContext:_context];
  glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
  [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
  glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_fbWidth);
  glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_fbHeight);

  glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderbuffer);

  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    NSLog(@"Z3View: incomplete framebuffer (0x%x)", status);
  }
  _layoutDirty = NO;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  _layoutDirty = YES;
}

#pragma mark - Start/stop

- (void)start {
  [self stop];
  _lastSerial = 0;
  _layoutDirty = YES;
  _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  // iOS 9.3 has no useful preferredFramesPerSecond throttling here: fire
  // every vsync and let the serial check make a no-op tick cheap.
  [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
  [_displayLink invalidate];
  _displayLink = nil;
}

#pragma mark - Per-frame

- (void)uploadFrame:(const Z3Frame *)f {
  [EAGLContext setCurrentContext:_context];
  glBindTexture(GL_TEXTURE_2D, _texture);

  // GL_UNPACK_ROW_LENGTH lets us upload directly from Z3Runtime's buffer at
  // its real pitch, in pixels, without a packing copy first -- pitch is
  // documented as bytes/row and every row in this engine is 4-byte BGRA, so
  // pitch/4 is exact.
  glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint)(f->pitch / 4));

  if (f->width != _texW || f->height != _texH) {
    // Only grows/reallocates on a real geometry change (e.g. extended
    // aspect ratio or 240-line toggle), not every frame.
    _texW = f->width;
    _texH = f->height;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _texW, _texH, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, f->pixels);
  } else {
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, f->width, f->height,
                     GL_RGBA, GL_UNSIGNED_BYTE, f->pixels);
  }

  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);

  if (f->width != _gameW || f->height != _gameH) {
    _gameW = f->width;
    _gameH = f->height;
  }
}

- (void)drawFrame {
  if (_layoutDirty) [self updateDrawable];
  if (_fbWidth <= 0 || _fbHeight <= 0 || _gameW <= 0 || _gameH <= 0) return;

  glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
  glViewport(0, 0, _fbWidth, _fbHeight);
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);

  // Aspect-correct letterbox, same math as the old CALayer path.
  CGFloat viewAspect = (CGFloat)_fbWidth / (CGFloat)_fbHeight;
  CGFloat gameAspect = (CGFloat)_gameW / (CGFloat)_gameH;
  CGFloat sx = 1.0f, sy = 1.0f;
  if (viewAspect > gameAspect) {
    sx = gameAspect / viewAspect;
  } else {
    sy = viewAspect / gameAspect;
  }

  // Two triangles as a strip, position (clip space) + texcoord.
  // Texture is stored top-row-first from the engine; flip V so it's not
  // upside down on screen (GL's texture origin is bottom-left).
  const GLfloat verts[] = {
    // x,      y,      u,    v
    -sx,  sy,   0.0f, 0.0f,
    -sx, -sy,   0.0f, 1.0f,
     sx,  sy,   1.0f, 0.0f,
     sx, -sy,   1.0f, 1.0f,
  };

  glBindBuffer(GL_ARRAY_BUFFER, _vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_DYNAMIC_DRAW);

  glUseProgram(_program);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, _texture);
  glUniform1i(_uTexture, 0);

  glEnableVertexAttribArray(_aPosition);
  glVertexAttribPointer(_aPosition, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (void *)0);
  glEnableVertexAttribArray(_aTexCoord);
  glVertexAttribPointer(_aTexCoord, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (void *)(2 * sizeof(GLfloat)));

  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
  [_context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)tick:(CADisplayLink *)link {
  (void)link;
  Z3Frame f;
  if (Z3Runtime_AcquireFrame(_lastSerial, &f)) {
    _lastSerial = f.serial;
    [self uploadFrame:&f];
    // Bytes are already copied into the GPU texture by uploadFrame:, so the
    // engine-owned buffer can be recycled immediately -- no need to hold it
    // until a compositor finishes reading it, unlike the old CGImage path.
    Z3Runtime_ReleaseFrame(f.handle);
  }
  // Redraw every vsync even if no new frame arrived yet, so the letterbox
  // stays correct across rotation/resizes and the drawable is never left
  // showing a stale/garbage buffer after a layout change.
  [self drawFrame];
}

#pragma mark - Touch mapping

- (CGPoint)viewPointToGameUnit:(CGPoint)pt {
  if (_gameW <= 0 || _gameH <= 0 || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
    return CGPointMake(-1, -1);
  }
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

  CGFloat ux = (pt.x - f.origin.x) / f.size.width;
  CGFloat uy = (pt.y - f.origin.y) / f.size.height;
  return CGPointMake(ux, uy);
}

@end
