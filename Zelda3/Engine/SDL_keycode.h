// SDL_keycode.h -- SDL-free stand-in for the engine core (iOS 9.3 / armv7 port).
//
// The engine's config.c packs keyboard bindings into uint16 tables using the
// numeric values of SDL2's SDLK_* constants, and zelda3.ini stores key *names*.
// We do not ship SDL, but we keep the numeric values byte-identical to SDL2 so
// that config.c and its tables stay untouched (no fork of engine logic).
//
// Values are copied from SDL2 2.x SDL_keycode.h / SDL_scancode.h.
#ifndef ZELDA3_SDL_KEYCODE_STANDIN_H_
#define ZELDA3_SDL_KEYCODE_STANDIN_H_

#include <stdint.h>

typedef int32_t SDL_Keycode;
typedef int     SDL_Keymod;

#define SDLK_SCANCODE_MASK (1 << 30)
#define SDL_SCANCODE_TO_KEYCODE(x) ((x) | SDLK_SCANCODE_MASK)

// scancodes we need (SDL_scancode.h)
#define SDL_SCANCODE_F1        58
#define SDL_SCANCODE_F2        59
#define SDL_SCANCODE_F3        60
#define SDL_SCANCODE_F4        61
#define SDL_SCANCODE_F5        62
#define SDL_SCANCODE_F6        63
#define SDL_SCANCODE_F7        64
#define SDL_SCANCODE_F8        65
#define SDL_SCANCODE_F9        66
#define SDL_SCANCODE_F10       67
#define SDL_SCANCODE_RIGHT     79
#define SDL_SCANCODE_LEFT      80
#define SDL_SCANCODE_DOWN      81
#define SDL_SCANCODE_UP        82
#define SDL_SCANCODE_LCTRL     224
#define SDL_SCANCODE_LSHIFT    225
#define SDL_SCANCODE_LALT      226
#define SDL_SCANCODE_RCTRL     228
#define SDL_SCANCODE_RSHIFT    229
#define SDL_SCANCODE_RALT      230

enum {
  SDLK_UNKNOWN = 0,
  SDLK_RETURN  = '\r',
  SDLK_TAB     = '\t',
  SDLK_a = 'a', SDLK_c = 'c', SDLK_e = 'e', SDLK_f = 'f', SDLK_k = 'k',
  SDLK_l = 'l', SDLK_o = 'o', SDLK_p = 'p', SDLK_r = 'r', SDLK_s = 's',
  SDLK_t = 't', SDLK_v = 'v', SDLK_w = 'w', SDLK_x = 'x', SDLK_z = 'z',

  SDLK_F1  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F1),
  SDLK_F2  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F2),
  SDLK_F3  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F3),
  SDLK_F4  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F4),
  SDLK_F5  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F5),
  SDLK_F6  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F6),
  SDLK_F7  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F7),
  SDLK_F8  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F8),
  SDLK_F9  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F9),
  SDLK_F10 = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_F10),
  SDLK_RIGHT  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RIGHT),
  SDLK_LEFT   = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LEFT),
  SDLK_DOWN   = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_DOWN),
  SDLK_UP     = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_UP),
  SDLK_LCTRL  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LCTRL),
  SDLK_LSHIFT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LSHIFT),
  SDLK_LALT   = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_LALT),
  SDLK_RCTRL  = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RCTRL),
  SDLK_RSHIFT = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RSHIFT),
  SDLK_RALT   = SDL_SCANCODE_TO_KEYCODE(SDL_SCANCODE_RALT),
};

// SDL_Keymod bits (SDL_keycode.h)
enum {
  KMOD_LSHIFT = 0x0001, KMOD_RSHIFT = 0x0002,
  KMOD_LCTRL  = 0x0040, KMOD_RCTRL  = 0x0080,
  KMOD_LALT   = 0x0100, KMOD_RALT   = 0x0200,
  KMOD_CTRL  = KMOD_LCTRL | KMOD_RCTRL,
  KMOD_SHIFT = KMOD_LSHIFT | KMOD_RSHIFT,
  KMOD_ALT   = KMOD_LALT | KMOD_RALT,
};

// Parses a key name from zelda3.ini ("Up", "F1", "Return", "a", ...).
// Returns SDLK_UNKNOWN for names we don't support (touch device: irrelevant).
SDL_Keycode SDL_GetKeyFromName(const char *name);

#endif  // ZELDA3_SDL_KEYCODE_STANDIN_H_
