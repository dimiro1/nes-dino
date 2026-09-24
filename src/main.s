; ===========================================================================
;  The Chrome dinosaur game, for the NES
; ===========================================================================
;  NROM, 32KB of program and 8KB of tiles, vertical mirroring so the two
;  nametables sit side by side and the world can scroll sideways through them.
;
;  A frame goes: the NMI hands last frame's work to the PPU, waits for the
;  sprite-0 hit that ends the fixed score bar, points the rest of the screen
;  at the camera, and returns.  The main loop then has the whole visible frame
;  to think in, and leaves its results in the OAM buffer and the PPU queue for
;  the next NMI to pick up.
; ===========================================================================

.include "nes.inc"
.include "game.inc"
.include "../build/tiles.inc"

; ---------------------------------------------------------------------------
;  Zero page
; ---------------------------------------------------------------------------
.segment "ZEROPAGE"

frame_count:    .res 1
pad1:           .res 1              ; buttons held now
pad1_prev:      .res 1
pad1_new:       .res 1              ; buttons that went down this frame

ppu_ctrl:       .res 1              ; shadow, nametable bits always clear
ppu_mask:       .res 1
scroll_lo:      .res 1              ; camera low byte, for the split
scroll_nt:      .res 1              ; camera bit 8, as a nametable select
queue_ready:    .res 1

game_state:     .res 1
state_timer:    .res 1

cam_frac:       .res 1              ; camera is 16.8 fixed point
cam_lo:         .res 1
cam_hi:         .res 1
cam_delta:      .res 1              ; whole pixels it moved this frame
speed_lo:       .res 1              ; 8.8 px/frame
speed_hi:       .res 1
ramp_timer:     .res 1
last_col_cam:   .res 1              ; cam_lo & $F8 when the last column went out

dino_y:         .res 1              ; top edge, pixels
dino_y_frac:    .res 1
dino_vel_lo:    .res 1              ; 8.8, signed, negative is upward
dino_vel_hi:    .res 1
dino_state:     .res 1
dino_anim:      .res 1
dino_timer:     .res 1

gen_run:        .res 1              ; columns left in the obstacle being drawn
gen_gap:        .res 1              ; columns of clear ground still to draw
gen_next:       .res 1              ; what starts when that gap runs out
gen_kind:       .res 1
gen_step:       .res 1

mtn_run:        .res 1              ; columns left in the mountain being drawn
mtn_step:       .res 1              ; which of its columns this one is
mtn_height:     .res 1              ; rows, and half its width
mtn_gap:        .res 1              ; columns of clear horizon still to draw
col_ready:      .res 1
col_target:     .res 1              ; 0..63, which nametable column is next

obst_kind:      .res NUM_OBST
obst_x_lo:      .res NUM_OBST       ; biased by POS_BIAS so compares stay unsigned
obst_x_hi:      .res NUM_OBST

ptero_on:       .res 1
ptero_x_lo:     .res 1
ptero_x_hi:     .res 1
ptero_y:        .res 1
ptero_anim:     .res 1
ptero_timer:    .res 1

cloud_x_lo:     .res NUM_CLOUDS
cloud_x_hi:     .res NUM_CLOUDS
cloud_frac:     .res NUM_CLOUDS
cloud_y:        .res NUM_CLOUDS

score:          .res 5              ; one digit a byte, most significant first
hi_score:       .res 5
dist_acc:       .res 1
hundreds:       .res 1
flash_timer:    .res 1
night:          .res 1
night_count:    .res 1
pal_scheme:     .res 1              ; 0 is CLASSIC, and nothing but Select moves it
restart_phase:  .res 1
pal_dirty:      .res 1
score_dirty:    .res 1

sfx_id:         .res 1              ; pulse 1: tunes
sfx_step:       .res 1
sfx_last_hi:    .res 1
nsfx_id:        .res 1              ; noise: thumps, which run alongside them
nsfx_step:      .res 1

rng:            .res 2

tmp:            .res 12
ptr:            .res 2
nt_col_base:    .res 1              ; nametable column showing at screen x = 0
q_count:        .res 1
txt_row:        .res 1
txt_col:        .res 1
txt_len:        .res 1
oam_idx:        .res 1
nmi_tmp:        .res 2

blit_x_lo:      .res 1
blit_x_hi:      .res 1
blit_y:         .res 1
blit_tile:      .res 1
blit_attr:      .res 1              ; which sprite palette the block is drawn in
blit_w:         .res 1
blit_h:         .res 1

; ---------------------------------------------------------------------------
;  Everything else
; ---------------------------------------------------------------------------
.segment "BSS"
ppu_queue:      .res 200
queue_len:      .res 1
col_buf:        .res COL_ROWS

.segment "OAMBUF"
oam:            .res 256

; ---------------------------------------------------------------------------
;  iNES header.  Mapper 0, vertical mirroring -- the two nametables end up
;  side by side, which is what a sideways scroll needs.
; ---------------------------------------------------------------------------
.segment "HEADER"
        .byte "NES", $1A
        .byte 2                     ; 2 x 16KB program
        .byte 1                     ; 1 x 8KB tiles
        .byte %00000001             ; vertical mirroring, no battery, mapper 0
        .byte %00000000
        .byte 0, 0, 0, 0, 0, 0, 0, 0

; ===========================================================================
.segment "CODE"

; ---------------------------------------------------------------------------
;  reset
; ---------------------------------------------------------------------------
reset:
        sei
        cld
        ldx #$40
        stx APUFRAME                ; no APU frame interrupt
        ldx #$FF
        txs
        inx                         ; x = 0
        stx PPUCTRL                 ; no NMI yet
        stx PPUMASK                 ; and nothing drawn
        stx $4010                   ; no DMC interrupt
        bit PPUSTATUS

@vblank1:
        bit PPUSTATUS
        bpl @vblank1

        ; Wipe the RAM.  OAM's copy is filled with $FF instead, which parks
        ; every sprite below the bottom of the screen.
        lda #0
        tax
@wipe:
        sta $0000,x
        sta $0100,x
        sta $0300,x
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        pha
        lda #$FF
        sta $0200,x
        pla
        inx
        bne @wipe

@vblank2:
        bit PPUSTATUS
        bpl @vblank2

        jsr sound_init
        jsr game_init

        lda #PPUCTRL_BASE
        sta ppu_ctrl
        sta PPUCTRL                 ; NMI on from here
        lda #PPUMASK_ON
        sta ppu_mask

; ---------------------------------------------------------------------------
;  The main loop.  One pass a frame, started by the NMI having incremented
;  frame_count and finished long before the next one.
; ---------------------------------------------------------------------------
main:
        lda frame_count
@wait:
        cmp frame_count
        beq @wait

        lda #0
        sta queue_ready
        sta queue_len

        jsr read_pad
        jsr palette_button

        lda restart_phase
        beq @dispatch
        jsr do_restart
        jmp @built

@dispatch:
        lda game_state
        cmp #ST_READY
        bne :+
        jsr state_ready
        jmp @built
:       cmp #ST_RUN
        bne :+
        jsr state_run
        jmp @built
:       cmp #ST_DYING
        bne :+
        jsr state_dying
        jmp @built
:       jsr state_over

@built:
        jsr build_oam
        jsr queue_frame_work
        jsr queue_terminate
        lda #1
        sta queue_ready
        jmp main

; ---------------------------------------------------------------------------
;  NMI -- the only place the PPU is ever touched while it is drawing
; ---------------------------------------------------------------------------
nmi:
        pha
        txa
        pha
        tya
        pha

        ; Sprites first: OAM DMA is the one transfer that must have a whole
        ; vblank in front of it.
        lda #0
        sta OAMADDR
        lda #>oam
        sta OAMDMA

        lda queue_ready
        beq @no_queue
        jsr ppu_flush_queue
@no_queue:

        ; The score bar: nametable 0, no scroll at all.
        lda ppu_ctrl
        sta PPUCTRL
        lda ppu_mask
        sta PPUMASK
        lda #0
        sta PPUSCROLL
        sta PPUSCROLL

        ; With rendering off there is no sprite 0 and no split to wait for.
        lda ppu_mask
        and #$18
        beq @no_split

        ; Last frame's hit is still flagged until the pre-render line clears
        ; it, so wait that out before watching for this frame's.
        ldx #0
@clear: bit PPUSTATUS
        bvc @clear_done
        inx
        bne @clear
        beq @no_split               ; never cleared: leave the scroll alone
@clear_done:

        ldx #0
@hit:   bit PPUSTATUS
        bvs @hit_done
        inx
        bne @hit
        ldy #0
@hit2:  bit PPUSTATUS
        bvs @hit_done
        iny
        bne @hit2
        beq @no_split               ; never hit: same
@hit_done:

        ; Scanline 23 has just gone by.  Everything below it belongs to the
        ; camera.
        lda ppu_ctrl
        ora scroll_nt
        sta PPUCTRL
        lda scroll_lo
        sta PPUSCROLL
        lda #0
        sta PPUSCROLL
@no_split:

        jsr sound_update

        inc frame_count
        pla
        tay
        pla
        tax
        pla
        rti

; ---------------------------------------------------------------------------
irq:
        rti

; ---------------------------------------------------------------------------
;  The controller.  Bits arrive A, B, Select, Start, Up, Down, Left, Right,
;  so rolling eight of them into a byte lands A in bit 7.
; ---------------------------------------------------------------------------
read_pad:
        lda pad1
        sta pad1_prev
        lda #1
        sta JOY1
        lda #0
        sta JOY1
        ldx #8
@loop:
        lda JOY1
        lsr a
        rol pad1
        dex
        bne @loop
        lda pad1_prev
        eor #$FF
        and pad1
        sta pad1_new
        rts

; ---------------------------------------------------------------------------
;  A 16-bit Galois shift register.  Seeded from the frame the player finally
;  pressed a button on, so two runs are never the same.
; ---------------------------------------------------------------------------
rand:
        lsr rng+1
        ror rng
        bcc @no_feedback
        lda rng+1
        eor #$B4
        sta rng+1
@no_feedback:
        lda rng
        eor rng+1
        rts

.include "ppu.s"
.include "palette.s"
.include "world.s"
.include "mountains.s"
.include "player.s"
.include "ptero.s"
.include "clouds.s"
.include "score.s"
.include "sound.s"
.include "render.s"
.include "states.s"
.include "data.s"

; ---------------------------------------------------------------------------
.segment "CHARS"
        .incbin "../build/dino.chr"

.segment "VECTORS"
        .word nmi, reset, irq
