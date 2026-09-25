// Z3View.h -- presents Z3Runtime frames via GLES2.
//
// Rewritten from the original CALayer/CGImage version: that path composited
// through Core Animation's shared render server, which on iOS 9.3 (A5-class
// GPU, iPad mini 1) produced visible horizontal banding on this port even
// after fixing contentsScale and wrapping the assignment in a CATransaction.
// This version owns the whole pipeline -- EAGLContext, a single RGBA8
// texture reused every frame, one textured quad -- so there is no compositor
// hand-off in between "pixels are ready" and "pixels are on screen".
#import <UIKit/UIKit.h>

@interface Z3View : UIView

// Starts/stops the CADisplayLink that pulls frames from Z3Runtime and
// uploads them to the GL texture. Does not start or stop the game thread.
- (void)start;
- (void)stop;

// Converts a touch location in this view to normalized [0,1]x[0,1] game-area
// coordinates (letterboxed inside the view, aspect-correct).
- (CGPoint)viewPointToGameUnit:(CGPoint)pt;

@end
