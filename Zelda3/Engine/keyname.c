// keyname.c -- SDL_GetKeyFromName() replacement (subset), SDL-free.
#include "SDL_keycode.h"
#include <string.h>
#include <ctype.h>

typedef struct { const char *name; SDL_Keycode key; } KeyName;

static const KeyName kNames[] = {
  {"Up", SDLK_UP}, {"Down", SDLK_DOWN}, {"Left", SDLK_LEFT}, {"Right", SDLK_RIGHT},
  {"Return", SDLK_RETURN}, {"Tab", SDLK_TAB},
  {"Left Shift", SDLK_LSHIFT}, {"Right Shift", SDLK_RSHIFT},
  {"Left Ctrl", SDLK_LCTRL}, {"Right Ctrl", SDLK_RCTRL},
  {"Left Alt", SDLK_LALT}, {"Right Alt", SDLK_RALT},
  {"F1", SDLK_F1}, {"F2", SDLK_F2}, {"F3", SDLK_F3}, {"F4", SDLK_F4}, {"F5", SDLK_F5},
  {"F6", SDLK_F6}, {"F7", SDLK_F7}, {"F8", SDLK_F8}, {"F9", SDLK_F9}, {"F10", SDLK_F10},
};

static int EqNoCase(const char *a, const char *b) {
  for (; *a && *b; a++, b++)
    if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
  return *a == *b;
}

SDL_Keycode SDL_GetKeyFromName(const char *name) {
  if (!name || !*name) return SDLK_UNKNOWN;
  // single printable character: SDL lowercases letters (keycode == ASCII, lowercase)
  if (name[1] == 0) {
    unsigned char c = (unsigned char)name[0];
    if (c >= 0x21 && c < 0x7f) return (SDL_Keycode)tolower(c);
  }
  for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); i++)
    if (EqNoCase(name, kNames[i].name)) return kNames[i].key;
  return SDLK_UNKNOWN;
}
