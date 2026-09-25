# Zelda3 (armv7 / iOS 9.3) — Theos application
# Built with the iPhoneOS 9.3 SDK, deployment target 9.3 (matches ShevaPDS's
# proven toolchain setup; MinimumOSVersion is also 9.3 in Resources/Info.plist
# since this port targets exactly that OS, unlike ShevaPDS's wider 7.0 range).
TARGET := iphone:clang:9.3:9.3
ARCHS = armv7

# Same clang-19-vs-old-SDK-modulemap workaround as ShevaPDS.
export ADDITIONAL_OBJCFLAGS += -Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Zelda3ARMv7

# Baseline applies to both .c and .m: -fobjc-arc/-fno-objc-arc only affect
# Objective-C translation units, so it is harmless on the plain-C engine files
# below -- ARC itself is enabled per-file for the .m files via _FILE_FLAGS,
# since Theos (like the gnustep-make it is built on) does not expose separate
# CFLAGS/OBJCFLAGS variables that route to .c vs .m independently.
Zelda3ARMv7_CFLAGS = -O2 -std=gnu11 -I$(THEOS_PROJECT_DIR)/Zelda3/Engine -I$(THEOS_PROJECT_DIR)/Zelda3/Platform \
	-I$(THEOS_PROJECT_DIR)/third_party/opus-1.3.1-stripped \
	-Wno-deprecated-declarations -Wno-unknown-warning-option \
	-Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map \
	-Wno-error=nullability-completeness -Wno-nullability-completeness \
	-Wno-error=unused-command-line-argument -Wno-unused-command-line-argument \
	-Wno-error=incomplete-umbrella -Wno-incomplete-umbrella \
	-Wno-error=non-modular-include-in-framework-module \
	-Wno-non-modular-include-in-framework-module \
	-Wno-error=non-modular-include-in-module -Wno-non-modular-include-in-module \
	-Wno-error=bitwise-op-parentheses -Wno-bitwise-op-parentheses \
	-Wno-error=logical-op-parentheses -Wno-logical-op-parentheses \
	-Wno-error=parentheses -Wno-parentheses \
	-Wno-error=unused-variable -Wno-unused-variable \
	-Wno-error=unused-but-set-variable -Wno-unused-but-set-variable \
	-Wno-error=deprecated-non-prototype -Wno-deprecated-non-prototype \
	-mno-unaligned-access

Zelda3ARMv7_FILES = \
	Zelda3/Engine/src/ancilla.c \
	Zelda3/Engine/src/attract.c \
	Zelda3/Engine/src/audio.c \
	Zelda3/Engine/src/config.c \
	Zelda3/Engine/src/dungeon.c \
	Zelda3/Engine/src/ending.c \
	Zelda3/Engine/src/hud.c \
	Zelda3/Engine/src/load_gfx.c \
	Zelda3/Engine/src/messaging.c \
	Zelda3/Engine/src/misc.c \
	Zelda3/Engine/src/nmi.c \
	Zelda3/Engine/src/overlord.c \
	Zelda3/Engine/src/overworld.c \
	Zelda3/Engine/src/player.c \
	Zelda3/Engine/src/player_oam.c \
	Zelda3/Engine/src/poly.c \
	Zelda3/Engine/src/select_file.c \
	Zelda3/Engine/src/spc_player.c \
	Zelda3/Engine/src/sprite.c \
	Zelda3/Engine/src/sprite_main.c \
	Zelda3/Engine/src/tagalong.c \
	Zelda3/Engine/src/tile_detect.c \
	Zelda3/Engine/src/util.c \
	Zelda3/Engine/src/zelda_rtl.c \
	Zelda3/Engine/snes/apu.c \
	Zelda3/Engine/snes/dma.c \
	Zelda3/Engine/snes/dsp.c \
	Zelda3/Engine/snes/ppu.c \
	Zelda3/Engine/snes/spc.c \
	Zelda3/Engine/snes/tracing.c \
	Zelda3/Engine/keyname.c \
	third_party/opus-1.3.1-stripped/opus_decoder_amalgam.c \
	Zelda3/Platform/bus_stubs.c \
	Zelda3/Platform/Z3Runtime.m \
	Zelda3/Platform/Z3View.m \
	Zelda3/Platform/Z3Audio.m \
	Zelda3/App/AppDelegate.m \
	Zelda3/App/GameViewController.m \
	Zelda3/App/TouchButton.m

# NOTE: intentionally NOT compiled -- see comments where each is referenced:
#   Engine/src/main.c, opengl.c, glsl_shader.c   (SDL/GL desktop entry point; replaced by Platform/)
#   Engine/src/zelda_cpu_infra.c                 (reference 65816 emulator: desktop-only ROM
#                                                  verification harness, never called at runtime)
#   Engine/snes/{cpu,snes,cart,input,snes_other}.c (belong to that same reference emulator;
#                                                  their headers are still included for struct
#                                                  typedefs used by ppu.h/dma.h -- see bus_stubs.c)

# ARC only for the ObjC platform/app files; the engine core and bus_stubs.c
# are plain C and unaffected by this flag either way, but being explicit here
# avoids ever silently ARC-ifying a future .m file added to the engine tree.
Zelda3/Platform/Z3Runtime.m_FILE_FLAGS = -fobjc-arc
Zelda3/Platform/Z3View.m_FILE_FLAGS = -fobjc-arc
Zelda3/Platform/Z3Audio.m_FILE_FLAGS = -fobjc-arc
Zelda3/App/AppDelegate.m_FILE_FLAGS = -fobjc-arc
Zelda3/App/GameViewController.m_FILE_FLAGS = -fobjc-arc
Zelda3/App/TouchButton.m_FILE_FLAGS = -fobjc-arc

# Third-party (unmodified libopus, stripped-decoder build): the amalgam
# includes an internal encoder-side stub (ec_encode_bin) and a helper
# (smooth_fade) that this decoder-only configuration never calls. That's
# upstream's code shape, not ours to edit, so silence just this warning
# for just this file rather than patching vendored source.
third_party/opus-1.3.1-stripped/opus_decoder_amalgam.c_FILE_FLAGS = -Wno-error=unused-function -Wno-unused-function

Zelda3ARMv7_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AudioToolbox AVFoundation OpenGLES
Zelda3ARMv7_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
