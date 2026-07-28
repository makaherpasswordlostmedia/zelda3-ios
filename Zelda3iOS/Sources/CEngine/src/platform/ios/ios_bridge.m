// iOS platform bridge implementation.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <SDL.h>
#include <SDL_syswm.h>
#include "ios_bridge.h"

// Declared by SDL2 (SDL_main.h) — the engine's real entry point in main.c
// is compiled as SDL's "main", SDL then calls back into this exported
// symbol name on platforms (like iOS) where SDL owns process bootstrap.
extern int SDL_main(int argc, char *argv[]);

static NSString *DocumentsPath(void) {
  NSArray<NSString *> *paths =
      NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  return paths.firstObject;
}

int ios_bridge_setup_documents_cwd(void) {
  NSString *docs = DocumentsPath();
  if (!docs)
    return 0;
  const char *path = docs.fileSystemRepresentation;
  mkdir(path, 0755); // no-op if it already exists
  if (chdir(path) != 0) {
    NSLog(@"ios_bridge: failed to chdir into Documents: %s", strerror(errno));
    return 0;
  }
  return 1;
}

int ios_bridge_has_rom_or_assets(void) {
  NSString *docs = DocumentsPath();
  if (!docs)
    return 0;
  NSFileManager *fm = NSFileManager.defaultManager;
  BOOL hasAssets = [fm fileExistsAtPath:[docs stringByAppendingPathComponent:@"zelda3_assets.dat"]];
  BOOL hasRom = [fm fileExistsAtPath:[docs stringByAppendingPathComponent:@"zelda3.sfc"]];
  return (hasAssets || hasRom) ? 1 : 0;
}

int ios_bridge_import_rom(const char *src_path) {
  if (!src_path)
    return 0;

  NSString *srcPath = [NSString stringWithUTF8String:src_path];
  NSString *docs = DocumentsPath();
  if (!docs)
    return 0;
  NSString *dstPath = [docs stringByAppendingPathComponent:@"zelda3.sfc"];

  NSFileManager *fm = NSFileManager.defaultManager;
  NSError *error = nil;

  // Remove any previous ROM so re-importing a different file doesn't merge
  // with stale extracted assets from an older ROM version.
  if ([fm fileExistsAtPath:dstPath]) {
    [fm removeItemAtPath:dstPath error:nil];
  }
  NSString *staleAssets = [docs stringByAppendingPathComponent:@"zelda3_assets.dat"];
  if ([fm fileExistsAtPath:staleAssets]) {
    [fm removeItemAtPath:staleAssets error:nil];
  }

  BOOL ok = [fm copyItemAtPath:srcPath toPath:dstPath error:&error];
  if (!ok) {
    NSLog(@"ios_bridge: failed to import ROM: %@", error);
    return 0;
  }
  return 1;
}

int ios_bridge_run_game(int argc, char **argv) {
  return SDL_main(argc, argv);
}

// --- Window-ready notification ------------------------------------------
//
// SDL_CreateWindow() on iOS creates and owns a real UIWindow internally.
// The engine's game loop runs SDL_main on a background thread (see
// GameViewController.swift, which dispatches ios_bridge_run_game onto a
// background queue), but UIKit objects must only be touched from the main
// thread — so this hop deliberately bounces onto dispatch_async(main).

static IosWindowReadyCallback g_window_ready_callback = NULL;
static void *g_window_ready_context = NULL;

void ios_bridge_set_window_ready_callback(IosWindowReadyCallback callback, void *context) {
  g_window_ready_callback = callback;
  g_window_ready_context = context;
}

void ios_bridge_notify_window_created(struct SDL_Window *window) {
  // Called from the engine's background thread, right after
  // SDL_CreateWindow() returns in main.c. Extract the real UIWindow via
  // SDL's syswm API, then hop to the main thread before touching UIKit or
  // invoking the (Swift) callback.
  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  if (!SDL_GetWindowWMInfo((SDL_Window *)window, &info)) {
    NSLog(@"ios_bridge: SDL_GetWindowWMInfo failed: %s", SDL_GetError());
    return;
  }
  if (info.subsystem != SDL_SYSWM_UIKIT) {
    NSLog(@"ios_bridge: unexpected window subsystem %d (expected UIKit)", info.subsystem);
    return;
  }

  UIWindow *uiWindow = info.info.uikit.window;
  if (!uiWindow)
    return;

  // Bridge-retain across the C callback boundary: CFBridgingRetain hands
  // ownership to the raw pointer we pass through `void*`; the Swift side
  // (via Unmanaged<UIWindow>.fromOpaque(...).takeRetainedValue()) takes
  // ownership back and releases it. This avoids the object being
  // deallocated between here and the callback firing on the main thread.
  void *retainedWindowRef = (void *)CFBridgingRetain(uiWindow);

  IosWindowReadyCallback callback = g_window_ready_callback;
  void *context = g_window_ready_context;
  if (!callback) {
    // No one registered a callback (yet, or ever) — release immediately to
    // avoid leaking; Swift will simply not get the overlay-attach hook.
    CFBridgingRelease(retainedWindowRef);
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    callback(retainedWindowRef, context);
  });
}
