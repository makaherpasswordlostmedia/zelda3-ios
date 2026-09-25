// Z3View.h -- presents Z3Runtime frames.
// Modeled on ShevaPDS's CrtView (CALayer.contents, no drawRect:, CADisplayLink),
// but uses a zero-copy CGDataProvider instead of CGBitmapContextCreateImage,
// because Z3Runtime hands out real engine-owned buffers that must be returned
// via Z3Runtime_ReleaseFrame() -- copying them (as CrtView does for its own
// offscreen context) would defeat the whole point of the buffer pool.
#import <UIKit/UIKit.h>

@interface Z3View : UIView

// Starts/stops the CADisplayLink that pulls frames from Z3Runtime and pushes
// them to the layer. Does not start or stop the game thread itself.
- (void)start;
- (void)stop;

// Converts a touch location in this view to normalized [0,1]x[0,1] game-area
// coordinates (letterboxed inside the view, aspect-correct).
- (CGPoint)viewPointToGameUnit:(CGPoint)pt;

@end
