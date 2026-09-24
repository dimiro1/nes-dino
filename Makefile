# ---------------------------------------------------------------------------
#  make          build build/dino.nes
#  make run      build it and play it
#  make test     build it and run the headless checks
#  make art      rebuild the tiles and the preview sheets only
#  make debug    build the three test-only variants
#
#  Needs cc65 (ca65 and ld65) and Lua.  The emulator is found on its own:
#  $MYNES if you set it, else one lying about near the project, else it asks,
#  else it fetches a release.  See tools/mynes.lua.
# ---------------------------------------------------------------------------

LUA    ?= lua
ROM     = build/dino.nes
CHR     = build/dino.chr
TILEINC = build/tiles.inc
SOURCES = $(wildcard src/*.s) $(wildcard src/*.inc)
ART     = $(wildcard assets/*.tiles)

all: $(ROM)

$(CHR) $(TILEINC): $(ART) tools/mktiles.lua tools/png.lua
	$(LUA) tools/mktiles.lua

build/dino.o: src/main.s $(SOURCES) $(CHR) $(TILEINC)
	ca65 -g -o $@ -I src --create-dep build/dino.d src/main.s

$(ROM): build/dino.o src/dino.cfg
	ld65 -C src/dino.cfg -o $@ -Ln build/dino.labels build/dino.o

art: $(CHR)

run: $(ROM)
	java -jar "$$($(LUA) tools/mynes.lua)" $(ROM)

test: $(ROM) debug
	$(LUA) tools/playtest.lua

# Test builds.  fast brings the birds and the night forward so a short run
# reaches them; god additionally turns collision off, so a run can be left to
# climb the score unattended; birds has the fast thresholds and no cacti, so
# only a bird can end a run.  None of them is the game.
debug: build/dino-fast.nes build/dino-god.nes build/dino-birds.nes

build/dino-fast.nes: $(SOURCES) $(CHR) $(TILEINC)
	ca65 -g -D DEBUG_FAST=1 -o build/dino-fast.o -I src src/main.s
	ld65 -C src/dino.cfg -o $@ -Ln build/dino-fast.labels build/dino-fast.o

build/dino-god.nes: $(SOURCES) $(CHR) $(TILEINC)
	ca65 -g -D DEBUG_FAST=1 -D DEBUG_GODMODE=1 -o build/dino-god.o -I src src/main.s
	ld65 -C src/dino.cfg -o $@ -Ln build/dino-god.labels build/dino-god.o

build/dino-birds.nes: $(SOURCES) $(CHR) $(TILEINC)
	ca65 -g -D DEBUG_FAST=1 -D DEBUG_NOCACTUS=1 -o build/dino-birds.o -I src src/main.s
	ld65 -C src/dino.cfg -o $@ -Ln build/dino-birds.labels build/dino-birds.o

clean:
	rm -rf build/*.o build/*.nes build/*.d build/*.labels build/*.chr \
	       build/tiles.inc build/test build/dbg build/shots

.PHONY: all run test art debug clean
