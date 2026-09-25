// bus_stubs.c -- link-time stand-ins for the reference 65816 emulator's bus.
//
// snes/dma.c calls snes_read/snes_write/snes_readBBus/snes_writeBBus only from
// dma_initHdma()/dma_doHdma()/dma_doDma(). The game core never calls those:
// ZeldaDrawPpuFrame() uses its own SimpleHdma (zelda_rtl.c) and only calls
// dma_startDma() (flag setting) + dma_write() (register latching). The bus
// functions are exercised solely by the optional reference emulator, which this
// port does not ship (ROM verification is a desktop debugging aid, and running a
// second CPU emulator every frame would halve the frame rate on an A5/A6).
//
// If one of these is ever reached, that is a bug -> fail loudly, do not guess.
#include "snes/snes.h"
#include "src/types.h"
#include <stdio.h>
#include <stdlib.h>

static void BusUnreachable(const char *fn) {
  char msg[96];
  snprintf(msg, sizeof(msg), "internal error: %s reached without reference emulator", fn);
  Die(msg);
}
uint8_t snes_read(Snes *s, uint32_t a)               { (void)s; (void)a; BusUnreachable("snes_read");  return 0; }
void    snes_write(Snes *s, uint32_t a, uint8_t v)   { (void)s; (void)a; (void)v; BusUnreachable("snes_write"); }
uint8_t snes_readBBus(Snes *s, uint8_t a)            { (void)s; (void)a; BusUnreachable("snes_readBBus");  return 0; }
void    snes_writeBBus(Snes *s, uint8_t a, uint8_t v){ (void)s; (void)a; (void)v; BusUnreachable("snes_writeBBus"); }
