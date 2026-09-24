; ---------------------------------------------------------------------------
;  game.inc -- the numbers the whole game agrees on
; ---------------------------------------------------------------------------

; --- the screen -------------------------------------------------------------
;  Scanlines 0..23 are the score bar and do not scroll; a sprite-0 hit on
;  scanline 23 is what hands the rest of the screen over to the camera.
STATUS_ROWS   = 3                  ; nametable rows 0..2
SPR0_X        = 8
SPR0_Y        = 22                 ; OAM y, so the sprite's first line is 23

GROUND_Y      = 192                ; the line everything stands on
ROW_GROUND    = GROUND_Y / 8       ; 24 -- nametable row holding that line
ROW_COL_TOP   = ROW_GROUND - 3     ; 21 -- first row a new column rewrites
COL_ROWS      = 5                  ; rows 21..25: cactus, cactus, cactus, line, grit

; --- the dino ---------------------------------------------------------------
DINO_X        = 24                 ; fixed; the world moves instead
DINO_W        = 24
DINO_H        = 24
DINO_TOP      = GROUND_Y - DINO_H  ; 168, standing on the line
DUCK_W        = 32
DUCK_H        = 16
DUCK_TOP      = GROUND_Y - DUCK_H  ; 176

; Hitbox, inset from the drawing so a near miss reads as a miss
HIT_L         = 3
HIT_R         = 20                 ; standing:  x DINO_X+3 .. DINO_X+20
HIT_R_DUCK    = 28                 ; ducking:   x DINO_X+3 .. DINO_X+28
HIT_T         = 2

; Jump: -4.6 px/frame against 0.22 px/frame^2 peaks at 48px after 21 frames,
; which clears the 24px large cactus with room and lands 42 frames later.
JUMP_VEL_LO   = $66                ; -4.6 px/frame, 8.8, as $FB66
JUMP_VEL_HI   = $FB
GRAVITY       = $38                ; 0.22 px/frame^2
GRAVITY_FAST  = $C0                ; held Down while airborne: drop like a stone
VEL_CUT_LO    = $40                ; releasing A trims the climb to -1.75 px/frame
VEL_CUT_HI    = $FE
MIN_JUMP_H    = 28                 ; ...but never below this, so a tap still
                                   ; clears a 24px cactus.  A held button
                                   ; reaches 48px; the gap between the two is
                                   ; the whole of the timing in the game.

; --- the world --------------------------------------------------------------
SPEED_START   = $01C0              ; 1.75 px/frame
SPEED_MAX     = $0580              ; 5.5 px/frame -- kept under 8 so one new
                                   ; nametable column a frame is always enough
SPEED_RAMP    = 8                  ; frames between +1/256 px of speed

; --- obstacles --------------------------------------------------------------
NUM_OBST      = 6

; A column is written 34 ahead of the screen's left edge, which puts it two
; columns past the right edge -- off screen when it is written and still off
; screen a frame later when the NMI uploads it.  An obstacle born in that
; column therefore starts 272px out, and everything x is biased by 512 so the
; 16-bit compares can stay unsigned all the way down to it leaving on the left.
SPAWN_X       = 272
POS_BIAS      = 512
COL_AHEAD     = 34
OB_NONE       = 0
OB_SMALL1     = 1
OB_SMALL2     = 2
OB_SMALL3     = 3
OB_LARGE1     = 4
OB_LARGE2     = 5
OB_PTERO      = 6                  ; a bird is an obstacle like any other

CACTUS_S_TOP  = GROUND_Y - 16      ; 176
CACTUS_L_TOP  = GROUND_Y - 24      ; 168

; --- the pterodactyl --------------------------------------------------------
PTERO_W       = 24
PTERO_H       = 16
PTERO_DRIFT   = 1                  ; px/frame faster than the ground

; Because it flies faster than the ground moves, a bird closes on whatever is
; in front of it all the way down the screen -- at the slowest speed it makes
; up about 90 pixels before it reaches the dino.  So the run of clear ground
; in front of a bird is this much longer than an ordinary one, and the dino
; never meets a cactus and a bird at the same moment.
PTERO_LEAD    = 14                 ; extra columns of gap, 112 pixels of it
PTERO_LOW     = 176                ; overlaps a ducking dino: jump it
PTERO_MID     = 160                ; overlaps a standing dino only: duck it
PTERO_HIGH    = 144                ; clears both: only a badly timed jump hits it

; --- clouds -----------------------------------------------------------------
NUM_CLOUDS    = 3
CLOUD_W       = 24

; --- game states ------------------------------------------------------------
ST_READY      = 0
ST_RUN        = 1
ST_DYING      = 2
ST_OVER       = 3

; --- scoring ----------------------------------------------------------------
DIST_PER_POINT = 16                ; pixels of ground per point

; Reaching 300 points honestly takes a couple of minutes of good play, which
; is no way to check that the birds and the night even work.  Assembling with
; -D DEBUG_FAST=1 brings both forward so a twenty-second headless run sees
; them; it changes nothing else.
.ifdef DEBUG_FAST
PTERO_AFTER    = 1                 ; hundreds of points before the first bird
NIGHT_EVERY    = 1                 ; hundreds between day and night
.else
PTERO_AFTER    = 3
NIGHT_EVERY    = 7
.endif

; --- PPU setup --------------------------------------------------------------
;  Backgrounds live in the first half of the CHR, sprites in the second.
PPUCTRL_BASE  = %10001000
PPUMASK_ON    = %00011110
