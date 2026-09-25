// TouchButton.h -- a translucent round button that tracks its own touch and
// reports pressed/released via a block, supporting multiple simultaneous
// buttons on screen (each UIView gets its own touches in UIKit's multitouch
// model, so no manual touch-to-button routing is needed here).
#import <UIKit/UIKit.h>

@interface TouchButton : UIControl
@property (nonatomic, copy) NSString *label;
+ (instancetype)buttonWithLabel:(NSString *)label;
@end

// Eight-way d-pad. Reports a bitmask of kZ3Btn_Up/Down/Left/Right (diagonals
// set two bits, matching how a physical d-pad or two arrow keys would).
@interface TouchDPad : UIControl
@end
