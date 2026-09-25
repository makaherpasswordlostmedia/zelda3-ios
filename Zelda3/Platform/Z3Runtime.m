// Z3Runtime.m -- see Z3Runtime.h for the threading model.
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <mach/mach_time.h>

#include "Z3Runtime.h"

#include "src/types.h"
#include "src/variables.h"
#include "src/zelda_rtl.h"
#include "src/config.h"
#include "src/assets.h"
#include "src/load_gfx.h"
#include "src/util.h"
#include "src/audio.h"
#include "snes/ppu.h"

// ---------------------------------------------------------------------------
// Engine-facing contract (the only symbols the emulator-free core needs)
// ---------------------------------------------------------------------------
const uint8 *g_asset_ptrs[kNumberOfAssets];
uint32 g_asset_sizes[kNumberOfAssets];

MemBlk FindInAssetArray(int asset, int idx) {
  return FindIndexInMemblk((MemBlk){ g_asset_ptrs[asset], g_asset_sizes[asset] }, idx);
}

// Recursive: the engine takes ZeldaApuLock() internally while callers here may
// already hold it (same nesting the desktop main.c has).
static pthread_mutex_t g_apu_mutex;
static pthread_once_t g_apu_mutex_once = PTHREAD_ONCE_INIT;
static void InitApuMutex(void) {
  pthread_mutexattr_t a;
  pthread_mutexattr_init(&a);
  pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
  pthread_mutex_init(&g_apu_mutex, &a);
  pthread_mutexattr_destroy(&a);
}
void ZeldaApuLock(void)   { pthread_once(&g_apu_mutex_once, InitApuMutex); pthread_mutex_lock(&g_apu_mutex); }
void ZeldaApuUnlock(void) { pthread_mutex_unlock(&g_apu_mutex); }

static Z3FatalHandler g_fatal_handler;
void Z3Runtime_SetFatalHandler(Z3FatalHandler h) { g_fatal_handler = h; }

void NORETURN Die(const char *error) {
  fprintf(stderr, "Zelda3 fatal: %s\n", error);
  if (g_fatal_handler) g_fatal_handler(error);
  // Handler is expected not to return; if it does, park this thread instead of
  // exit()ing from a background thread (which raced the alert in the old port).
  for (;;) sleep(3600);
}

// ---------------------------------------------------------------------------
// Runtime state
// ---------------------------------------------------------------------------
// Buffer ownership (model-checked; a naive "showing/latest" scheme was found to let the
// game overwrite an image Core Animation was still reading):
//   FREE    - nobody uses it; only FREE buffers may be written
//   WRITING - the game thread is drawing into it (at most one)
//   READY   - newest finished frame, waiting for the UI (at most one; superseded ones go FREE)
//   HELD    - owned by a CGImage/Core Animation until its provider release callback fires
enum { kNumBuffers = 4 };
enum { kBufFree = 0, kBufWriting, kBufReady, kBufHeld };

static struct {
  uint8_t *buf[kNumBuffers];   // ARGB8888
  int width, height;
  size_t pitch;
  int render_scale_alloc;      // 1 or 4 (allocated per-pixel scale)

  pthread_mutex_t buf_lock;    // guards buf_state / ready_index; held only for a few instructions
  int buf_state[kNumBuffers];
  int ready_index;             // -1 = none
  _Atomic uint32_t latest_serial;
  uint32_t skipped_frames;     // frames not drawn because no FREE buffer existed (stat)

  _Atomic uint32_t buttons;
  _Atomic int paused;
  _Atomic int running;
  _Atomic int stop_requested;
  _Atomic int pending_cmd;     // 0 none, 1 save, 2 load, 3 reset
  _Atomic int pending_slot;

  int audio_rate;
  int audio_channels;
  int frames_per_block;        // engine block size (534 * rate / 32000)
  int16_t *audio_block;
  int audio_block_cur, audio_block_len; // in int16 units

  uint32 ppu_render_flags;
  pthread_t thread;
  int thread_started;
  int prepared;
} g;

static uint64_t NowNs(void) {
  static mach_timebase_info_data_t tb;
  if (tb.denom == 0) mach_timebase_info(&tb);
  return mach_absolute_time() * tb.numer / tb.denom;
}

// ---------------------------------------------------------------------------
// Asset loading (logic taken verbatim from the desktop main.c LoadAssets)
// ---------------------------------------------------------------------------
static int LoadAssetsFrom(const char *docs, const char *bundle, char *err, size_t err_size) {
  char path[1024];
  size_t length = 0;
  uint8 *data = NULL;

  snprintf(path, sizeof(path), "%s/zelda3_assets.dat", docs);
  data = ReadWholeFile(path, &length);

  if (!data) {
    snprintf(path, sizeof(path), "%s/zelda3_assets.bps", bundle);
    size_t bps_len = 0;
    uint8 *bps = ReadWholeFile(path, &bps_len);
    if (!bps) { snprintf(err, err_size, "Missing zelda3_assets.bps in app bundle."); return 1; }

    snprintf(path, sizeof(path), "%s/zelda3.sfc", docs);
    size_t rom_len = 0;
    uint8 *rom = ReadWholeFile(path, &rom_len);
    if (!rom) {
      free(bps);
      snprintf(err, err_size, "ROM not found. Copy zelda3.sfc (US) into the app via iTunes File Sharing.");
      return 2;
    }
    // Many dumps (.smc) carry a 512-byte copier header; the BPS expects exactly
    // 1 MiB (CRC32 777aac2f). Strip the header when the size says it is present.
    uint8 *rom_body = rom;
    if (rom_len == 1048576 + 512) { rom_body = rom + 512; rom_len -= 512; }
    data = ApplyBps(rom_body, rom_len, bps, bps_len, &length);
    free(rom); free(bps);
    if (!data) {
      snprintf(err, err_size, "This ROM does not match. A US 'zelda3.sfc' (no header) is required.");
      return 3;
    }
    // Cache the extracted assets so the ROM is not needed again (as upstream does).
    snprintf(path, sizeof(path), "%s/zelda3_assets.dat", docs);
    FILE *f = fopen(path, "wb");
    if (f) { fwrite(data, 1, length, f); fclose(f); }
  }

  static const char kAssetsSig[] = { kAssets_Sig };
  if (length < 16 + 32 + 32 + 8 + kNumberOfAssets * 4 ||
      memcmp(data, kAssetsSig, 48) != 0 ||
      memcmp(data + 80, &(uint32){ kNumberOfAssets }, 4) != 0) {
    snprintf(err, err_size, "Invalid assets file (wrong version?).");
    return 4;
  }

  // NOTE: the desktop code dereferences these as *(uint32*) directly. Asset blobs
  // start at arbitrary byte offsets, so on armv7 use memcpy for the header reads.
  uint32 hdr84; memcpy(&hdr84, data + 84, 4);
  uint32 offset = 88 + kNumberOfAssets * 4 + hdr84;
  for (size_t i = 0; i < kNumberOfAssets; i++) {
    uint32 size; memcpy(&size, data + 88 + i * 4, 4);
    offset = (offset + 3) & ~3u;
    if ((uint64)offset + size > length) { snprintf(err, err_size, "Assets file is corrupt."); return 5; }
    g_asset_sizes[i] = size;
    g_asset_ptrs[i]  = data + offset;
    offset += size;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Prepare / Start / Stop
// ---------------------------------------------------------------------------
int Z3Runtime_Prepare(const char *documents_dir, const char *bundle_dir, char *err, size_t err_size) {
  if (g.prepared) return 0;
  err[0] = 0;

  // The engine reads zelda3.user.ini / zelda3.ini and writes saves/ relative to cwd.
  mkdir(documents_dir, 0755);
  if (chdir(documents_dir) != 0) { snprintf(err, err_size, "Cannot enter Documents."); return 10; }
  mkdir("saves", 0755);

  // Seed a mobile-tuned config on first run; never overwrite a user's edits.
  char src[1024], dst[1024];
  snprintf(dst, sizeof(dst), "%s/zelda3.ini", documents_dir);
  if (access(dst, F_OK) != 0) {
    snprintf(src, sizeof(src), "%s/zelda3.ios.ini", bundle_dir);
    NSData *d = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:src]];
    if (d) [d writeToFile:[NSString stringWithUTF8String:dst] atomically:YES];
  }

  ParseConfigFile(NULL);

  int rc = LoadAssetsFrom(documents_dir, bundle_dir, err, err_size);
  if (rc) return rc;

  ZeldaInitialize();
  g_zenv.ppu->extraLeftRight = UintMin(g_config.extended_aspect_ratio, kPpuExtraLeftRight);
  g.width  = g_config.extended_aspect_ratio * 2 + 256;
  g.height = g_config.extend_y ? 240 : 224;

  g_wanted_zelda_features = g_config.features0;
  // 4x4 mode-7 is forced off: 1024x896 output is far beyond an A5/A6 budget.
  g.ppu_render_flags = g_config.new_renderer * kPpuRenderFlags_NewRenderer |
                       g_config.extend_y * kPpuRenderFlags_Height240 |
                       g_config.no_sprite_limits * kPpuRenderFlags_NoSpriteLimits;
  g.render_scale_alloc = 1;

  ZeldaEnableMsu(0);  // MSU needs Opus, which this port does not ship.
  ZeldaSetLanguage(g_config.language);

  g.pitch = (size_t)g.width * 4;
  for (int i = 0; i < kNumBuffers; i++) {
    g.buf[i] = calloc(g.pitch * g.height, 1);
    if (!g.buf[i]) { snprintf(err, err_size, "Out of memory."); return 11; }
  }
  pthread_mutex_init(&g.buf_lock, NULL);
  for (int i = 0; i < kNumBuffers; i++) g.buf_state[i] = kBufFree;
  g.ready_index = -1;

  g.audio_rate = 44100;
  g.audio_channels = 2;
  g.frames_per_block = (534 * g.audio_rate) / 32000;
  g.audio_block = calloc((size_t)g.frames_per_block * g.audio_channels, sizeof(int16_t));
  g.audio_block_cur = g.audio_block_len = 0;

  ZeldaReadSram();
  if (g_config.autosave) SaveLoadSlot(kSaveLoad_Load, 0);

  g.prepared = 1;
  return 0;
}

static void *GameThreadMain(void *unused) {
  (void)unused;
  pthread_setname_np("zelda3.game");
  uint64_t next = NowNs();
  uint32_t frame_ctr = 0;

  while (!atomic_load(&g.stop_requested)) {
    if (atomic_load(&g.paused)) { usleep(16000); next = NowNs(); continue; }

    // Commands run on the game thread so they never race the frame.
    int cmd = atomic_exchange(&g.pending_cmd, 0);
    if (cmd) {
      int slot = atomic_load(&g.pending_slot);
      ZeldaApuLock();
      if (cmd == 1) SaveLoadSlot(kSaveLoad_Save, slot);
      else if (cmd == 2) SaveLoadSlot(kSaveLoad_Load, slot);
      else if (cmd == 3) ZeldaReset(true);
      ZeldaApuUnlock();
    }

    int inputs = (int)atomic_load(&g.buttons);
    ZeldaApuLock();
    ZeldaRunFrame(inputs);
    ZeldaApuUnlock();
    frame_ctr++;

    // Claim a FREE buffer. If Core Animation still holds every spare one, skip drawing
    // this frame (game logic and audio already advanced) instead of overwriting a
    // buffer that is on screen.
    int wi = -1;
    pthread_mutex_lock(&g.buf_lock);
    for (int i = 0; i < kNumBuffers; i++)
      if (g.buf_state[i] == kBufFree) { g.buf_state[i] = kBufWriting; wi = i; break; }
    pthread_mutex_unlock(&g.buf_lock);

    if (wi >= 0) {
      ZeldaDrawPpuFrame(g.buf[wi], g.pitch, g.ppu_render_flags);
      pthread_mutex_lock(&g.buf_lock);
      if (g.ready_index >= 0) g.buf_state[g.ready_index] = kBufFree;  // superseded, never shown
      g.buf_state[wi] = kBufReady;
      g.ready_index = wi;
      pthread_mutex_unlock(&g.buf_lock);
      atomic_fetch_add(&g.latest_serial, 1);
    } else {
      g.skipped_frames++;
    }

    // 60 fps pacing with the same 17/17/16 ms cadence as the desktop build.
    static const uint32_t kDelayMs[3] = { 17, 17, 16 };
    next += (uint64_t)kDelayMs[frame_ctr % 3] * 1000000ull;
    uint64_t now = NowNs();
    if (next > now) {
      uint64_t d = next - now;
      if (d > 500000000ull) { next = now; d = 0; }
      usleep((useconds_t)(d / 1000));
    } else if (now - next > 500000000ull) {
      next = now;  // fell far behind: resync instead of fast-forwarding
    }
  }
  atomic_store(&g.running, 0);
  return NULL;
}

int Z3Runtime_Start(void) {
  if (!g.prepared || g.thread_started) return -1;
  atomic_store(&g.stop_requested, 0);
  atomic_store(&g.running, 1);
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 1 << 20);  // engine has deep call chains (sprite/dungeon)
  int rc = pthread_create(&g.thread, &attr, GameThreadMain, NULL);
  pthread_attr_destroy(&attr);
  if (rc != 0) { atomic_store(&g.running, 0); return rc; }
  g.thread_started = 1;
  return 0;
}

void Z3Runtime_Stop(void) {
  if (!g.thread_started) return;
  atomic_store(&g.stop_requested, 1);
  pthread_join(g.thread, NULL);
  g.thread_started = 0;
  if (g_config.autosave) { ZeldaApuLock(); SaveLoadSlot(kSaveLoad_Save, 0); ZeldaApuUnlock(); }
  ZeldaWriteSram();
}

// ---------------------------------------------------------------------------
// Input / control
// ---------------------------------------------------------------------------
void Z3Runtime_SetButtons(uint32_t mask) { atomic_store(&g.buttons, mask & 0x0fff); }
void Z3Runtime_SetPaused(int p) { atomic_store(&g.paused, p ? 1 : 0); }
void Z3Runtime_SaveState(int slot) { atomic_store(&g.pending_slot, slot); atomic_store(&g.pending_cmd, 1); }
void Z3Runtime_LoadState(int slot) { atomic_store(&g.pending_slot, slot); atomic_store(&g.pending_cmd, 2); }
void Z3Runtime_Reset(void) { atomic_store(&g.pending_cmd, 3); }

// ---------------------------------------------------------------------------
// Video
// ---------------------------------------------------------------------------
int Z3Runtime_AcquireFrame(uint32_t last_serial, Z3Frame *out) {
  if (atomic_load(&g.latest_serial) == last_serial) return 0;
  int idx = -1;
  pthread_mutex_lock(&g.buf_lock);
  if (g.ready_index >= 0) {
    idx = g.ready_index;
    g.buf_state[idx] = kBufHeld;   // exclusive until Z3Runtime_ReleaseFrame(idx)
    g.ready_index = -1;
  }
  pthread_mutex_unlock(&g.buf_lock);
  if (idx < 0) return 0;
  out->pixels = g.buf[idx];
  out->width = g.width;
  out->height = g.height;
  out->pitch = g.pitch;
  out->serial = atomic_load(&g.latest_serial);
  out->handle = idx;
  return 1;
}

// Called from the CGDataProvider release callback (any thread) once Core Animation
// no longer reads the pixels.
void Z3Runtime_ReleaseFrame(int handle) {
  if (handle < 0 || handle >= kNumBuffers) return;
  pthread_mutex_lock(&g.buf_lock);
  if (g.buf_state[handle] == kBufHeld) g.buf_state[handle] = kBufFree;
  pthread_mutex_unlock(&g.buf_lock);
}

uint32_t Z3Runtime_SkippedFrames(void) { return g.skipped_frames; }

// ---------------------------------------------------------------------------
// Audio: same block-splitting scheme as the desktop AudioCallback.
// ---------------------------------------------------------------------------
int Z3Runtime_AudioSampleRate(void) { return 44100; }

void Z3Runtime_RenderAudio(int16_t *out, int frames) {
  if (!g.prepared || !atomic_load(&g.running)) {
    memset(out, 0, (size_t)frames * 2 * sizeof(int16_t));
    return;
  }
  int want = frames * g.audio_channels;   // int16 units
  while (want > 0) {
    if (g.audio_block_cur >= g.audio_block_len) {
      ZeldaRenderAudio(g.audio_block, g.frames_per_block, g.audio_channels);
      g.audio_block_cur = 0;
      g.audio_block_len = g.frames_per_block * g.audio_channels;
    }
    int n = g.audio_block_len - g.audio_block_cur;
    if (n > want) n = want;
    memcpy(out, g.audio_block + g.audio_block_cur, (size_t)n * sizeof(int16_t));
    g.audio_block_cur += n;
    out += n;
    want -= n;
  }
  ZeldaApuLock();
  ZeldaDiscardUnusedAudioFrames();
  ZeldaApuUnlock();
}
