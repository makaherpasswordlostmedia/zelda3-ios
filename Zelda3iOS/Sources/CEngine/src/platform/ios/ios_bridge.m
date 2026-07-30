// iOS platform bridge implementation.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
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

// Raw POSIX write-ahead checkpoint, duplicated here (rather than calling
// into main.c's IosCheckpoint) so this file has zero dependency on
// main.c's internals and can log the very first instant control reaches
// ios_bridge_run_game — before SDL_main's own "SDL_main: entry" checkpoint,
// which only fires *inside* SDL_main after argc/argv have already been
// touched. If the app crashes between GameViewController.launchEngine()
// dispatching to this function and SDL_main's own first checkpoint, this
// is the only thing that can catch it.
static void EarlyCheckpoint(const char *stage) {
  NSString *docs = DocumentsPath();
  if (!docs)
    return;
  NSString *path = [docs stringByAppendingPathComponent:@"checkpoint.log"];
  int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (fd < 0)
    return;
  write(fd, stage, strlen(stage));
  write(fd, "\n", 1);
  close(fd);
}

int ios_bridge_run_game(int argc, char **argv) {
  EarlyCheckpoint("ios_bridge_run_game: entry (before SDL_main)");
  // The last crash we saw (EXC_CRASH/SIGABRT via libc++abi/libobjc, i.e. an
  // uncaught Objective-C exception) gave no readable message — just raw
  // addresses. Catching NSException here lets us surface *what* was thrown
  // instead of just that something crashed. This won't catch a raw
  // SIGSEGV/mach exception (e.g. a genuine NULL dereference in C code), but
  // most "uncaught exception" aborts on iOS come from Foundation/UIKit
  // calls (fopen-equivalents, NSFileManager, NSString, etc.) throwing on
  // unexpected input, which this will catch.
  @try {
    return SDL_main(argc, argv);
  } @catch (NSException *exception) {
    char buf[512];
    snprintf(buf, sizeof(buf), "Uncaught exception: %s: %s",
             exception.name.UTF8String ?: "(unknown)",
             exception.reason.UTF8String ?: "(no reason)");
    ios_bridge_notify_fatal_error(buf);
    return 1;
  }
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

void ios_bridge_notify_fatal_error_and_wait(const char *message, double timeout_seconds) {
  // Same idea as ios_bridge_notify_fatal_error(), but the caller (Die(), in
  // src/main.c) needs the main-thread callback to have actually run before
  // it calls exit(1) — otherwise exit() can race and win against the
  // dispatch_async'd UI update, killing the process before the alert is
  // ever shown. That produced a silent, log-less crash on device (seen on
  // iPhone 8 / iOS 14.7): the game would just disappear with nothing in
  // Console.app to explain why.
  IosFatalErrorCallback callback = g_fatal_error_callback;
  void *context = g_fatal_error_context;
  if (!callback)
    return;

  char *messageCopy = message ? strdup(message) : strdup("(unknown error)");

  if ([NSThread isMainThread]) {
    // Die() can technically be called from the main thread too (e.g. if a
    // future call site runs before the engine hops to its background
    // thread) — in that case dispatch_sync-ing to the main queue from the
    // main thread would deadlock, so just call directly.
    callback(messageCopy, context);
    free(messageCopy);
    return;
  }

  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_main_queue(), ^{
    callback(messageCopy, context);
    free(messageCopy);
    dispatch_semaphore_signal(sem);
  });
  // Bound the wait so a stuck/misbehaving main thread (e.g. blocked showing
  // some other alert) can't hang app termination forever — worst case we
  // just fall back to the old exit-without-alert behavior after the
  // timeout instead of hanging the process.
  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout_seconds * NSEC_PER_SEC)));
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

  // IMPORTANT: this used to be dispatch_sync, so the engine's background
  // thread would block until the Swift callback (attachControlsOverlay)
  // finished — including its retry loop, which busy-polled by calling
  // RunLoop.current.run(until:) *from inside this same dispatch_sync
  // block's execution on the main thread*.
  //
  // That combination is unsafe: GCD's dispatch_sync delivers this block to
  // the main thread via the *dispatch queue* mechanism, not by handing
  // control to RunLoop.main in the normal way a run-loop source would. A
  // RunLoop.current.run() called from inside that GCD-delivered block does
  // not reliably pump the same sources SDL_CreateWindow's continuation
  // needs, because that continuation is itself waiting for *this*
  // dispatch_sync to return. The two threads end up waiting on each other:
  // the background thread blocks in dispatch_sync waiting for Swift, and
  // the retry loop on the main thread blocks waiting for state that only
  // changes once SDL's own main-thread work continues -- work that can't
  // run until dispatch_sync returns. iOS's launch watchdog then kills the
  // process outright (SIGKILL, "process-launch watchdog transgression")
  // well before any in-process crash/exception handler, checkpoint write,
  // or alert ever gets a chance to run -- which is exactly the "shows
  // controls for an instant, then just dies, absolutely nothing in any
  // log" symptom this was causing.
  //
  // Fix: dispatch_async instead, and wait for Swift to *signal* completion
  // via a semaphore with a bounded timeout, rather than letting GCD itself
  // hold the main queue hostage across a nested run-loop poll. This keeps
  // the "don't call SDL_CreateRenderer until the overlay is attached"
  // guarantee (we still block this background thread until attach
  // finishes or the timeout elapses) without ever nesting a busy-wait
  // inside the main thread's own dispatch_sync execution.
  dispatch_semaphore_t attachDone = dispatch_semaphore_create(0);
  __block void *blockContext = context;
  __block IosWindowReadyCallback blockCallback = callback;
  dispatch_async(dispatch_get_main_queue(), ^{
    blockCallback(retainedWindowRef, blockContext);
    dispatch_semaphore_signal(attachDone);
  });
  // 2s is generous for attaching a view hierarchy but still bounded, so a
  // pathological case can't hang the engine thread (and therefore the
  // whole app) forever -- worst case we just proceed to SDL_CreateRenderer
  // slightly before the overlay finishes attaching, same as the old
  // "give up after ~1s" fallback already did in the Swift retry loop.
  dispatch_semaphore_wait(attachDone, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
}
