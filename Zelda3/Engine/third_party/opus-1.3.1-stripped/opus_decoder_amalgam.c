#define HAVE_CONFIG_H

#include "entcode.h"

// Decoder-only build: these encoder-side stubs exist only to satisfy
// entcode.h's declarations pulled in by the shared header; none are
// called from this configuration. Silence -Wunused-function locally
// via pragma (works regardless of command-line flag ordering).
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
static inline void ec_enc_bit_logp(ec_enc *_this, int _val, unsigned _logp) {}
static inline void ec_enc_uint(ec_enc *_this, opus_uint32 _fl, opus_uint32 _ft) {}
static inline void ec_encode_bin(ec_enc *_this, unsigned _fl, unsigned _fh, unsigned _bits) {}
static inline void ec_enc_bits(ec_enc *_this, opus_uint32 _fl, unsigned _bits) {}
#pragma clang diagnostic pop


#include "bands.c"
#include "celt.c"
#include "celt_decoder.c"
#include "cwrs.c"
#include "entcode.c"
#include "entdec.c"
#include "opus.c"
// smooth_fade() inside opus_decoder.c is unused by this decoder-only
// amalgam configuration; same rationale as above.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#include "opus_decoder.c"
#pragma clang diagnostic pop
#include "kiss_fft.c"
#include "laplace.c"
#include "mathops.c"
#include "mdct.c"
#include "modes.c"
#include "x86/pitch_sse.c"
#include "x86/x86cpu.c"
#include "quant_bands.c"
#include "rate.c"
#include "vq.c"

