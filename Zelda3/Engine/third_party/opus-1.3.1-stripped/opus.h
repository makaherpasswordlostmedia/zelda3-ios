// opus.h -- stub for the iOS 9.3 armv7 port. MSU/Opus music is an optional
// feature (EnableMSU=false by default, no .opuz files on device). Instead of
// shipping ~18 Opus/CELT files (incl. ARM NEON asm), opus_decoder_create()
// reports failure; audio.c already handles that via its READ_ERROR path,
// which cleanly disables MSU. Game music comes from the built-in SPC/DSP.
#ifndef OPUS_STUB_H_
#define OPUS_STUB_H_
#include <stddef.h>
#include <stdint.h>
typedef struct OpusDecoder OpusDecoder;
#define OPUS_RESET_STATE 4028
static inline OpusDecoder *opus_decoder_create(int32_t fs, int channels, int *error) {
  (void)fs; (void)channels; if (error) *error = -1; return NULL;
}
static inline void opus_decoder_destroy(OpusDecoder *st) { (void)st; }
static inline int opus_decoder_ctl(OpusDecoder *st, int request, ...) { (void)st; (void)request; return -1; }
static inline int opus_decode(OpusDecoder *st, const unsigned char *data, int32_t len,
                              int16_t *pcm, int frame_size, int decode_fec) {
  (void)st; (void)data; (void)len; (void)pcm; (void)frame_size; (void)decode_fec; return -1;
}
#endif
