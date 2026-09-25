// AppDelegate.m
#import "AppDelegate.h"
#import "GameViewController.h"
#import <AVFoundation/AVFoundation.h>
#include "Z3Audio.h"
#include "Z3Runtime.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
  [[NSNotificationCenter defaultCenter] addObserver:self
      selector:@selector(handleAudioInterruption:)
      name:AVAudioSessionInterruptionNotification object:nil];

  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  self.window.rootViewController = [[GameViewController alloc] init];
  [self.window makeKeyAndVisible];
  return YES;
}

- (void)handleAudioInterruption:(NSNotification *)note {
  NSNumber *typeNum = note.userInfo[AVAudioSessionInterruptionTypeKey];
  if (typeNum.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
    Z3Audio_HandleInterruptionBegan();
  } else {
    Z3Audio_HandleInterruptionEnded();
  }
}

// Pausing on background is the App Store review requirement (no audio/CPU use
// while suspended) as well as the simplest way to avoid the game thread
// fighting the OS for CPU right as it is about to be frozen mid-frame.
- (void)applicationDidEnterBackground:(UIApplication *)application {
  Z3Runtime_SetPaused(1);
  Z3Audio_Stop();
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
  Z3Audio_Start();
  Z3Runtime_SetPaused(0);
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
