// TouchButton.m
#import "TouchButton.h"
#include "Z3Runtime.h"
#include <stdatomic.h>

// All touch controls OR their bit into this and call Z3Runtime_SetButtons with
// the combined result -- a single button's -touchesBegan: must not stomp on
// bits another button already set, since UIKit delivers each control's
// touches independently and concurrently.
static _Atomic uint32_t g_padMask;

static void UpdateMask(uint32_t bit, BOOL down) {
  uint32_t old, updated;
  do {
    old = atomic_load(&g_padMask);
    updated = down ? (old | bit) : (old & ~bit);
  } while (!atomic_compare_exchange_weak(&g_padMask, &old, updated));
  Z3Runtime_SetButtons(updated);
}

@implementation TouchButton {
  uint32_t _bit;
  UILabel *_titleLabel;
}

+ (instancetype)buttonWithLabel:(NSString *)label {
  TouchButton *b = [[self alloc] initWithFrame:CGRectZero];
  b.label = label;
  return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    self.layer.cornerRadius = 8;
    _titleLabel = [[UILabel alloc] initWithFrame:self.bounds];
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    _titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self addSubview:_titleLabel];
  }
  return self;
}

- (void)setLabel:(NSString *)label {
  _label = label;
  _titleLabel.text = label;
  // Button-name -> engine bit. Kept local to this view instead of a lookup
  // table shared across the app: this file is the only place button labels
  // are chosen or interpreted, so the mapping has exactly one place to change.
  static NSDictionary<NSString *, NSNumber *> *map;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    map = @{ @"A": @(kZ3Btn_A), @"B": @(kZ3Btn_B), @"X": @(kZ3Btn_X), @"Y": @(kZ3Btn_Y),
             @"L": @(kZ3Btn_L), @"R": @(kZ3Btn_R),
             @"Start": @(kZ3Btn_Start), @"Select": @(kZ3Btn_Select) };
  });
  _bit = map[label].unsignedIntValue;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.35];
  UpdateMask(_bit, YES);
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self release_]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self release_]; }
- (void)release_ {
  self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
  UpdateMask(_bit, NO);
}

@end

@implementation TouchDPad {
  uint32_t _currentBits;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    self.layer.cornerRadius = 8;
  }
  return self;
}

- (uint32_t)bitsForPoint:(CGPoint)pt {
  // Dead zone in the middle third; outer ring split into 8 directions so
  // diagonals (e.g. Up+Right) are reachable the way a real d-pad allows.
  CGPoint c = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
  CGFloat dx = pt.x - c.x, dy = pt.y - c.y;
  CGFloat r = MIN(c.x, c.y);
  if (dx * dx + dy * dy < (r * 0.28) * (r * 0.28)) return 0;
  uint32_t bits = 0;
  CGFloat angle = atan2(dy, dx);  // -pi..pi, 0 = right, +pi/2 = down (UIKit y-down)
  CGFloat deg = angle * 180.0 / M_PI;
  if (deg < 0) deg += 360;
  // 8 sectors of 45deg, centered on each cardinal/diagonal direction.
  if (deg >= 337.5 || deg < 22.5)        bits = kZ3Btn_Right;
  else if (deg < 67.5)                   bits = kZ3Btn_Right | kZ3Btn_Down;
  else if (deg < 112.5)                  bits = kZ3Btn_Down;
  else if (deg < 157.5)                  bits = kZ3Btn_Down | kZ3Btn_Left;
  else if (deg < 202.5)                  bits = kZ3Btn_Left;
  else if (deg < 247.5)                  bits = kZ3Btn_Left | kZ3Btn_Up;
  else if (deg < 292.5)                  bits = kZ3Btn_Up;
  else                                   bits = kZ3Btn_Up | kZ3Btn_Right;
  return bits;
}

- (void)applyBits:(uint32_t)newBits {
  static const uint32_t kDirMask = kZ3Btn_Up | kZ3Btn_Down | kZ3Btn_Left | kZ3Btn_Right;
  uint32_t old, updated;
  do {
    old = atomic_load(&g_padMask);
    updated = (old & ~kDirMask) | newBits;
  } while (!atomic_compare_exchange_weak(&g_padMask, &old, updated));
  Z3Runtime_SetButtons(updated);
  _currentBits = newBits;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self applyBits:[self bitsForPoint:[touches.anyObject locationInView:self]]];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self applyBits:[self bitsForPoint:[touches.anyObject locationInView:self]]];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self applyBits:0]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self applyBits:0]; }

@end
