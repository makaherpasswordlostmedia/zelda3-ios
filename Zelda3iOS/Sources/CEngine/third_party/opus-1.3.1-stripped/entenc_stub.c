/* entenc_stub.c
 *
 * This is a decode-only build of Opus/CELT: entenc.c (the real range-coder
 * encoder implementation) was intentionally stripped from this vendored
 * copy, along with entenc.h (see the commented-out `#include "entenc.h"`
 * lines throughout this directory).
 *
 * However, a few shared files (bands.c, rate.c, cwrs.c, quant_bands.c) call
 * ec_enc_bit_logp(), ec_enc_bits(), and ec_enc_uint() on branches guarded by
 * a *runtime* `if (encode)` check rather than a compile-time `#if
 * ENABLE_ENCODER` guard. Since this app never constructs an encoder
 * (Sources/CEngine/src/audio.c only ever calls opus_decoder_create /
 * opus_decode), those branches are never taken at runtime — but the
 * compiler still emits calls to them, so the linker needs the symbols to
 * exist somewhere.
 *
 * These are plain no-op stand-ins so the link succeeds. They must never
 * actually be reached in this decode-only build; the asserts make that
 * loud and immediate if that assumption is ever wrong (e.g. if encoder
 * support is added later without re-vendoring entenc.c).
 */

#include <assert.h>
#include "entcode.h"

void ec_enc_bit_logp(ec_enc *_this, int _val, unsigned _logp) {
  (void)_this; (void)_val; (void)_logp;
  assert(0 && "ec_enc_bit_logp called in a decode-only Opus build");
}

void ec_enc_bits(ec_enc *_this, opus_uint32 _fl, unsigned _bits) {
  (void)_this; (void)_fl; (void)_bits;
  assert(0 && "ec_enc_bits called in a decode-only Opus build");
}

void ec_enc_uint(ec_enc *_this, opus_uint32 _fl, opus_uint32 _ft) {
  (void)_this; (void)_fl; (void)_ft;
  assert(0 && "ec_enc_uint called in a decode-only Opus build");
}
