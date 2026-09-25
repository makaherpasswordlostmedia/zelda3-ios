// Z3Runtime.h -- SDL-free runtime for the Zelda3 engine on iOS 9.x armv7.
//
// Threading model (deliberately simple; the previous SDL-based port died from
// dispatch_sync-ing between a game thread and the main thread):
//   * Game thread  : runs ZeldaRunFrame + ZeldaDrawPpuFrame, writes into a back
//                    buffer. Never calls UIKit.
//   * Main thread  : CADisplayLink asks Z3Runtime_AcquireFrame() for the newest
//                    finished buffer and hands it to Core Animation.
//   * Audio thread : AudioQueue callback calls Z3Runtime_RenderAudio().
//   * Input        : UI thread writes an atomic button mask; game thread reads it.
// No thread ever blocks waiting for another one except the short engine-level
// ZeldaApuLock() mutex (shared by game + audio thread, as in the original).
#ifndef Z3_RUNTIME_H_
#define Z3_RUNTIME_H_

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Frame geometry. The 4x4 mode-7 path is disabled on this port (see zelda3.ios.ini),
// so the framebuffer is always g_width x g_height ARGB8888 (0x00RRGGBB in a uint32).
typedef struct Z3Frame {
  const uint8_t *pixels;   // BGRA in memory on little-endian ARM (== kCGBitmapByteOrder32Little)
  int width, height;
  size_t pitch;            // bytes per row
  uint32_t serial;         // increments once per finished frame
  int handle;              // pass to Z3Runtime_ReleaseFrame() when Core Animation is done
} Z3Frame;

// Joypad bits for ZeldaRunFrame(). This is NOT the SNES register order: the
// engine bit-reverses this word in NMI_ReadJoypads(). Layout verified by
// simulating that reversal and by matching the desktop port's kKbdRemap table
// (all 12 buttons agree).
enum {
  kZ3Btn_B      = 1 << 0,
  kZ3Btn_Y      = 1 << 1,
  kZ3Btn_Select = 1 << 2,
  kZ3Btn_Start  = 1 << 3,
  kZ3Btn_Up     = 1 << 4,
  kZ3Btn_Down   = 1 << 5,
  kZ3Btn_Left   = 1 << 6,
  kZ3Btn_Right  = 1 << 7,
  kZ3Btn_A      = 1 << 8,
  kZ3Btn_X      = 1 << 9,
  kZ3Btn_L      = 1 << 10,
  kZ3Btn_R      = 1 << 11,
};

// Callback used for fatal errors (Die()). Called on the thread that failed; the
// handler must not return into engine code (it should show UI and park/exit).
typedef void (*Z3FatalHandler)(const char *message);
void Z3Runtime_SetFatalHandler(Z3FatalHandler handler);

// Prepares assets. `documents_dir` must contain zelda3.sfc (US ROM) or a ready
// zelda3_assets.dat, plus zelda3_assets.bps (bundled). Returns 0 on success, or
// writes a human-readable reason into err (size err_size) and returns nonzero.
int Z3Runtime_Prepare(const char *documents_dir, const char *bundle_dir,
                      char *err, size_t err_size);

// Starts the game thread. Safe to call once after Z3Runtime_Prepare succeeded.
int Z3Runtime_Start(void);
void Z3Runtime_Stop(void);

// Input (any thread). Bits from the enum above.
void Z3Runtime_SetButtons(uint32_t mask);
void Z3Runtime_SetPaused(int paused);

// Video (main thread). Returns 1 and fills *out if a frame newer than last_serial
// exists. The buffer is owned by the caller until Z3Runtime_ReleaseFrame(out->handle)
// -- call that from the CGDataProvider release callback, NOT right after creating
// the CGImage, because Core Animation reads the pixels asynchronously.
int Z3Runtime_AcquireFrame(uint32_t last_serial, Z3Frame *out);
void Z3Runtime_ReleaseFrame(int handle);
uint32_t Z3Runtime_SkippedFrames(void);

// Audio (audio thread). Interleaved int16 stereo, `frames` sample frames.
// Fills silence if the engine is not running yet.
void Z3Runtime_RenderAudio(int16_t *out, int frames);

// Output rate the audio queue must be opened with.
int Z3Runtime_AudioSampleRate(void);

// Save-state slot commands, safe from any thread (take the audio lock).
void Z3Runtime_SaveState(int slot);
void Z3Runtime_LoadState(int slot);
void Z3Runtime_Reset(void);

#ifdef __cplusplus
}
#endif
#endif  // Z3_RUNTIME_H_
