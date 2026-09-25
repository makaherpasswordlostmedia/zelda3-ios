// Z3Audio.h -- AudioQueue output for the Zelda3 engine (iOS 9.3, armv7).
//
// AudioQueueServices instead of AVAudioEngine/AUAudioUnit: it has been stable
// since iOS 2 and needs no session-graph setup, which matters on iOS 9.3 where
// we cannot lean on newer AVFoundation defaults. Buffers are filled directly by
// Z3Runtime_RenderAudio() from the AudioQueue's own callback thread -- no extra
// ring buffer, since ZeldaApuLock() inside RenderAudio already makes that safe
// to call concurrently with the game thread.
#ifndef Z3_AUDIO_H_
#define Z3_AUDIO_H_

#ifdef __cplusplus
extern "C" {
#endif

// Starts audio output. Safe to call again after Z3Audio_Stop(). Returns 0 on
// success, or an OSStatus-derived nonzero code on failure (device/session issue,
// not fatal to the game -- caller should let the game run muted).
int Z3Audio_Start(void);
void Z3Audio_Stop(void);

// Call from the app's audio-interruption / route-change handlers.
void Z3Audio_HandleInterruptionBegan(void);
void Z3Audio_HandleInterruptionEnded(void);

#ifdef __cplusplus
}
#endif
#endif  // Z3_AUDIO_H_
