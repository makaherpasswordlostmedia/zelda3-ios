// GameViewController.m
#import "GameViewController.h"
#import "Z3View.h"
#import "TouchButton.h"
#include "Z3Runtime.h"
#include "Z3Audio.h"

@interface GameViewController ()
@end

@implementation GameViewController {
  Z3View *_gameView;
  UILabel *_statusLabel;
  UIButton *_pickRomButton;
  BOOL _started;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor blackColor];
  Z3Runtime_SetFatalHandler(FatalHandler);
  [self tryBoot];
}

// Die() in the engine calls this from whatever thread hit the fatal error
// (usually the game thread). UIKit calls must be hopped to the main thread.
// __weak on a file-scope global is not supported under the legacy
// (fragile) Objective-C runtime that armv7 always uses -- only the modern
// runtime (arm64/x86_64) supports weak references to non-instance-variable
// storage. Use __unsafe_unretained instead and clear it in -dealloc so we
// never dereference a dangling pointer.
static __unsafe_unretained GameViewController *g_currentVC;
static void FatalHandler(const char *message) {
  NSString *msg = [NSString stringWithUTF8String:message];
  dispatch_async(dispatch_get_main_queue(), ^{
    [g_currentVC showFatalAlert:msg];
  });
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  g_currentVC = self;
}

- (void)dealloc {
  if (g_currentVC == self) {
    g_currentVC = nil;
  }
}

- (NSString *)documentsDir {
  return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

- (void)tryBoot {
  char err[256] = {0};
  int rc = Z3Runtime_Prepare(self.documentsDir.UTF8String, [NSBundle mainBundle].bundlePath.UTF8String, err, sizeof(err));
  if (rc != 0) {
    [self showRomPicker:[NSString stringWithUTF8String:err]];
    return;
  }
  [self startGame];
}

- (void)startGame {
  if (_started) return;
  _started = YES;
  [_pickRomButton removeFromSuperview]; _pickRomButton = nil;
  [_statusLabel removeFromSuperview]; _statusLabel = nil;

  _gameView = [[Z3View alloc] initWithFrame:self.view.bounds];
  _gameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:_gameView];
  [self buildTouchOverlay];

  Z3Runtime_Start();
  Z3Audio_Start();
  [_gameView start];
}

// Simple on-screen instructions shown when no ROM was found yet: the app
// cannot legally bundle the ROM, and iOS 9.3 has no document picker (that
// API arrived in iOS 11), so iTunes File Sharing is the only route -- this
// screen just explains that and lets the user retry once they have copied it.
- (void)showRomPicker:(NSString *)reason {
  _statusLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 24, 24)];
  _statusLabel.numberOfLines = 0;
  _statusLabel.textColor = [UIColor whiteColor];
  _statusLabel.textAlignment = NSTextAlignmentCenter;
  _statusLabel.font = [UIFont systemFontOfSize:16];
  _statusLabel.text = [NSString stringWithFormat:
      @"%@\n\nConnect this device to a computer, open this app in iTunes File Sharing, "
      @"and copy your legally-owned zelda3.sfc (US release) into it. Then tap Retry.", reason];
  _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:_statusLabel];

  _pickRomButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_pickRomButton setTitle:@"Retry" forState:UIControlStateNormal];
  _pickRomButton.tintColor = [UIColor whiteColor];
  _pickRomButton.frame = CGRectMake(0, 0, 120, 44);
  _pickRomButton.center = CGPointMake(self.view.bounds.size.width / 2,
                                       self.view.bounds.size.height - 60);
  _pickRomButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
  [_pickRomButton addTarget:self action:@selector(tryBoot) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_pickRomButton];
}

- (void)showFatalAlert:(NSString *)message {
  UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Zelda3 crashed"
      message:message preferredStyle:UIAlertControllerStyleAlert];
  [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:ac animated:YES completion:nil];
}

- (void)buildTouchOverlay {
  CGRect b = self.view.bounds;
  CGFloat pad = 16, btnSize = 56;

  TouchDPad *dpad = [[TouchDPad alloc] initWithFrame:CGRectMake(pad, b.size.height - 3 * btnSize - pad, 3 * btnSize, 3 * btnSize)];
  dpad.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
  [self.view addSubview:dpad];

  CGFloat rx = b.size.width - pad - 2.4 * btnSize, ry = b.size.height - 2.4 * btnSize - pad;
  NSDictionary *positions = @{
    @"A": [NSValue valueWithCGPoint:CGPointMake(rx + 1.2 * btnSize, ry)],
    @"B": [NSValue valueWithCGPoint:CGPointMake(rx + 0.6 * btnSize, ry + 0.9 * btnSize)],
    @"X": [NSValue valueWithCGPoint:CGPointMake(rx + 0.6 * btnSize, ry - 0.9 * btnSize)],
    @"Y": [NSValue valueWithCGPoint:CGPointMake(rx, ry)],
  };
  for (NSString *name in positions) {
    TouchButton *btn = [TouchButton buttonWithLabel:name];
    CGPoint c = [positions[name] CGPointValue];
    btn.frame = CGRectMake(c.x, c.y, btnSize, btnSize);
    btn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:btn];
  }

  TouchButton *select = [TouchButton buttonWithLabel:@"Select"];
  select.frame = CGRectMake(b.size.width / 2 - 90, b.size.height - 40, 70, 28);
  select.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
  [self.view addSubview:select];

  TouchButton *start = [TouchButton buttonWithLabel:@"Start"];
  start.frame = CGRectMake(b.size.width / 2 + 20, b.size.height - 40, 70, 28);
  start.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
  [self.view addSubview:start];

  TouchButton *l = [TouchButton buttonWithLabel:@"L"];
  l.frame = CGRectMake(pad, pad, 60, 36);
  l.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
  [self.view addSubview:l];

  TouchButton *r = [TouchButton buttonWithLabel:@"R"];
  r.frame = CGRectMake(b.size.width - pad - 60, pad, 60, 36);
  r.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
  [self.view addSubview:r];
}

- (BOOL)prefersStatusBarHidden { return YES; }

@end
