// iOS platform bridge implementation.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <SDL.h>
#include "ios_bridge.h"

// SwiftSDL2 ships SDL2 as a precompiled XCFramework and only exposes the
// core cross-platform headers — SDL_syswm.h (and other platform-specific
// headers) are not part of its public module, so `#include <SDL_syswm.h>`
// can never resolve against this dependency. SDL_GetWindowWMInfo() is still
// exported by the compiled library and its ABI is stable, so we declare the
// minimal, layout-compatible subset of SDL_syswm.h we actually need
// (the UIKit case) locally instead of relying on the missing header.
// NOTE: SDL_SYSWM_TYPE is an enum whose numeric values are fixed by SDL2's
// public ABI. Re-declaring the full enum (in original member order) is the
// safe way to get a matching value for SDL_SYSWM_UIKIT without needing the
// header, since C enum constants must match across translation units by
// value, not just by name.
typedef enum {
  SDL_SYSWM_UNKNOWN,
  SDL_SYSWM_WINDOWS,
  SDL_SYSWM_X11,
  SDL_SYSWM_DIRECTFB,
  SDL_SYSWM_COCOA,
  SDL_SYSWM_UIKIT,
  SDL_SYSWM_WAYLAND,
  SDL_SYSWM_MIR,
  SDL_SYSWM_WINRT,
  SDL_SYSWM_ANDROID,
  SDL_SYSWM_VIVANTE,
  SDL_SYSWM_OS2,
  SDL_SYSWM_HAIKU,
  SDL_SYSWM_KMSDRM,
  SDL_SYSWM_RISCOS
} SDL_SYSWM_TYPE;

struct SDL_SysWMinfo {
  SDL_version version;
  SDL_SYSWM_TYPE subsystem;
  union {
    struct {
      UIWindow *window;
    } uikit;
    // Matches upstream SDL_syswm.h's "can't have an empty union" padding
    // member for platforms/subsystems we don't handle here.
    Uint8 dummy[64];
  } info;
};
typedef struct SDL_SysWMinfo SDL_SysWMinfo;

extern SDL_bool SDL_GetWindowWMInfo(SDL_Window *window, SDL_SysWMinfo *info);

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

static IosFatalErrorCallback g_fatal_error_callback = NULL;
static void *g_fatal_error_context = NULL;

void ios_bridge_set_fatal_error_callback(IosFatalErrorCallback callback, void *context) {
  g_fatal_error_callback = callback;
  g_fatal_error_context = context;
}

void ios_bridge_notify_fatal_error(const char *message) {
  // Called from Die() (src/main.c), which may be running on the engine's
  // background thread — hop to main before touching UIKit / invoking the
  // (Swift) callback, same pattern as ios_bridge_notify_window_created
  // below. We strdup the message because Die()'s caller may pass a literal
  // that's fine to reference immediately, but to be safe across the async
  // hop we take our own copy and free it after the callback returns.
  IosFatalErrorCallback callback = g_fatal_error_callback;
  void *context = g_fatal_error_context;
  if (!callback)
    return;
  char *messageCopy = message ? strdup(message) : strdup("(unknown error)");
  dispatch_async(dispatch_get_main_queue(), ^{
    callback(messageCopy, context);
    free(messageCopy);
  });
}

void ios_bridge_notify_window_created(struct SDL_Window *window) {
  // Called from the engine's background thread, right after
  // SDL_CreateWindow() returns in main.c. Extract the real UIWindow via
  // SDL's syswm API, then hop to the main thread before touching UIKit or
  // invoking the (Swift) callback.
  // SDL_SysWMinfo contains a union whose UIKit variant holds a
  // strong-qualified `UIWindow *`. ARC refuses to stack-allocate (or
  // default-initialize/destruct) any aggregate with a non-trivial union
  // member, so `SDL_SysWMinfo info;` on the stack fails to compile under
  // ARC. Heap-allocate it instead with plain calloc/free, which sidesteps
  // ARC's automatic retain/release entirely (the union is never
  // synthesized-managed on the heap the way it would be for a stack/ivar
  // declaration).
  SDL_SysWMinfo *infoPtr = (SDL_SysWMinfo *)calloc(1, sizeof(SDL_SysWMinfo));
  if (!infoPtr) {
    NSLog(@"ios_bridge: failed to allocate SDL_SysWMinfo");
    return;
  }
  SDL_VERSION(&infoPtr->version);
  if (!SDL_GetWindowWMInfo((SDL_Window *)window, infoPtr)) {
    NSLog(@"ios_bridge: SDL_GetWindowWMInfo failed: %s", SDL_GetError());
    free(infoPtr);
    return;
  }
  if (infoPtr->subsystem != SDL_SYSWM_UIKIT) {
    NSLog(@"ios_bridge: unexpected window subsystem %d (expected UIKit)", infoPtr->subsystem);
    free(infoPtr);
    return;
  }

  // Copy out the raw pointer value before freeing; __unsafe_unretained
  // avoids ARC trying to manage this local the same way it would the union.
  __unsafe_unretained UIWindow *uiWindow = infoPtr->info.uikit.window;
  free(infoPtr);
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
