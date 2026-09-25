// Z3Audio.m
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "Z3Audio.h"
#include "Z3Runtime.h"

// 3 buffers x ~23ms @44.1kHz stereo: enough slack that the callback (which
// calls into the engine's ZeldaApuLock()) is not on the critical path of
// every single vsync, but still short enough that pause/resume feels snappy.
enum { kNumAudioBuffers = 3, kFramesPerBuffer = 1024 };

static AudioQueueRef g_queue;
static BOOL g_running;

static void FillBuffer(AudioQueueBufferRef buf) {
  int frames = kFramesPerBuffer;
  buf->mAudioDataByteSize = (UInt32)(frames * 2 * sizeof(int16_t));
  Z3Runtime_RenderAudio((int16_t *)buf->mAudioData, frames);
}

static void AudioCallback(void *inUserData, AudioQueueRef queue, AudioQueueBufferRef buf) {
  (void)inUserData;
  FillBuffer(buf);
  AudioQueueEnqueueBuffer(queue, buf, 0, NULL);
}

static BOOL ConfigureSession(void) {
  NSError *err = nil;
  AVAudioSession *session = [AVAudioSession sharedInstance];
  // Ambient, not Playback: this is a game, not a music player -- respect the
  // silent switch and let other audio (podcasts, music) duck/mix as iOS decides,
  // instead of unilaterally taking over the audio session like a media app would.
  [session setCategory:AVAudioSessionCategoryAmbient error:&err];
  if (err) { NSLog(@"Z3Audio: setCategory failed: %@", err); return NO; }
  [session setActive:YES error:&err];
  if (err) { NSLog(@"Z3Audio: setActive failed: %@", err); return NO; }
  return YES;
}

int Z3Audio_Start(void) {
  if (g_running) return 0;
  if (!ConfigureSession()) return -1;

  AudioStreamBasicDescription fmt = {0};
  fmt.mSampleRate = Z3Runtime_AudioSampleRate();
  fmt.mFormatID = kAudioFormatLinearPCM;
  fmt.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  fmt.mBitsPerChannel = 16;
  fmt.mChannelsPerFrame = 2;
  fmt.mBytesPerFrame = 2 * sizeof(int16_t);
  fmt.mFramesPerPacket = 1;
  fmt.mBytesPerPacket = fmt.mBytesPerFrame;

  // NULL run loop: AudioQueue spins its own internal thread for the callback.
  // Passing CFRunLoopGetMain() here is a known cause of multi-second hangs in
  // AudioQueueStop() (observed and fixed upstream in VLC's audioqueue output).
  OSStatus st = AudioQueueNewOutput(&fmt, AudioCallback, NULL, NULL, NULL, 0, &g_queue);
  if (st != noErr) { g_queue = NULL; return (int)st; }

  for (int i = 0; i < kNumAudioBuffers; i++) {
    AudioQueueBufferRef buf;
    st = AudioQueueAllocateBuffer(g_queue, kFramesPerBuffer * 2 * sizeof(int16_t), &buf);
    if (st != noErr) { AudioQueueDispose(g_queue, true); g_queue = NULL; return (int)st; }
    FillBuffer(buf);
    AudioQueueEnqueueBuffer(g_queue, buf, 0, NULL);
  }

  st = AudioQueueStart(g_queue, NULL);
  if (st != noErr) { AudioQueueDispose(g_queue, true); g_queue = NULL; return (int)st; }
  g_running = YES;
  return 0;
}

void Z3Audio_Stop(void) {
  if (!g_queue) return;
  // Synchronous stop (true): safe here because we are called from the main
  // thread, never from AudioCallback itself, and the callback runs on
  // AudioQueue's own thread (see the NULL run loop above), so there is no
  // self-deadlock risk.
  AudioQueueStop(g_queue, true);
  AudioQueueDispose(g_queue, true);
  g_queue = NULL;
  g_running = NO;
}

void Z3Audio_HandleInterruptionBegan(void) {
  if (g_queue) AudioQueuePause(g_queue);
}

void Z3Audio_HandleInterruptionEnded(void) {
  if (!g_queue) return;
  if (ConfigureSession()) AudioQueueStart(g_queue, NULL);
}
