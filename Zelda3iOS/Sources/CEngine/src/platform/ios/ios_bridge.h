// iOS platform bridge.
//
// This is the seam between the Swift/UIKit app shell and the portable
// SDL2-based C engine in src/main.c. The engine itself is untouched aside
// from the small SwitchDirectory() patch in main.c; everything iOS-specific
// (sandbox paths, ROM import, lifecycle) lives here.
#ifndef IOS_BRIDGE_H
#define IOS_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Returns 1 if a ROM has already been imported and assets are ready to load
// (i.e. zelda3.sfc or zelda3_assets.dat exists in the app's Documents dir).
int ios_bridge_has_rom_or_assets(void);

// Copies the file at `src_path` (an absolute filesystem path obtained from
// a security-scoped URL / UIDocumentPicker) into the app sandbox's
// Documents directory as "zelda3.sfc". Returns 1 on success, 0 on failure.
// The caller (Swift) is responsible for starting/stopping
// NSURL.startAccessingSecurityScopedResource around this call.
int ios_bridge_import_rom(const char *src_path);

// chdir()s the process into the app's Documents directory and makes sure
// it's writable. Must be called once, before SDL_main/main() runs the
// engine's asset-loading code. Returns 1 on success.
int ios_bridge_setup_documents_cwd(void);

// Entry point called from Swift once a ROM/assets are confirmed present.
// This calls into SDL_main (i.e. the engine's real main()) and does not
// return until the game quits.
int ios_bridge_run_game(int argc, char **argv);

// On-screen button identifiers, in the same order as the engine's
// kDefaultGamepadCmds table (src/config.c) — this order is what
// HandleCommand(kKeys_Controls + N, ...) expects. Kept as an explicit enum
// here (rather than sharing config.h's internal kKeys_* enum) so the
// Swift-facing surface stays small and doesn't need every internal engine
// header on its include path.
typedef enum {
  kIosBtn_Up = 0,
  kIosBtn_Down = 1,
  kIosBtn_Left = 2,
  kIosBtn_Right = 3,
  kIosBtn_Select = 4,
  kIosBtn_Start = 5,
  kIosBtn_B = 6,
  kIosBtn_A = 7,
  kIosBtn_Y = 8,
  kIosBtn_X = 9,
  kIosBtn_L = 10,
  kIosBtn_R = 11,
} IosButton;

// Called from the on-screen touch controls overlay. `pressed` is 1 on
// touch-down, 0 on touch-up. Thread-safe to call from the UI thread even
// while the engine's game loop runs on its own thread — it just sets a bit
// in the same input state the engine already reads every frame.
void ios_bridge_set_button(IosButton button, int pressed);

// Opaque forward declaration to avoid pulling SDL.h into this header (kept
// minimal so Swift's bridging header stays SDL-free); ios_bridge.m includes
// SDL.h itself and does the real cast.
struct SDL_Window;

// Called once from main.c, right after SDL_CreateWindow succeeds, so the
// bridge can extract the underlying UIWindow and hand it to Swift. Not
// meant to be called from Swift directly.
void ios_bridge_notify_window_created(struct SDL_Window *window);

// Registers a callback invoked (on the main thread) once the real UIWindow
// backing the SDL window is available. Swift calls this once at startup,
// before launching the engine, so it knows when it's safe to attach the
// touch controls overlay on top of SDL's window. `uiWindowRef` is the
// UIWindow, bridged as `void*` (retained — see ios_bridge.m) so this header
// doesn't need to import UIKit. `context` is passed back unchanged — used
// to carry a reference to the calling Swift object across the C boundary
// without a global.
typedef void (*IosWindowReadyCallback)(void *uiWindowRef, void *context);
void ios_bridge_set_window_ready_callback(IosWindowReadyCallback callback, void *context);

#ifdef __cplusplus
}
#endif

#endif // IOS_BRIDGE_H
