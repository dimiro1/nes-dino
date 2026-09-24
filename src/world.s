; ===========================================================================
;  world.s -- the camera, the ground it uncovers, and the cacti standing in it
; ===========================================================================
;  The dino never moves horizontally.  The camera does, and everything else
;  is measured against it.
;
;  A new column of nametable is written every eight pixels of camera travel,
;  COL_AHEAD columns ahead of the screen's left edge -- which puts it two
;  columns beyond the right edge, off screen when it is written and still off
;  screen when the NMI uploads it a frame later.  A cactus born in that column
;  therefore starts life SPAWN_X pixels to the right of the screen and walks
;  in from there, one cam_delta at a time, so it can never drift out of step
;  with the tiles it is drawn from.
; ===========================================================================

.segment "CODE"

world_init:
        lda #0
        sta cam_frac
        sta cam_lo
        sta cam_hi
        sta cam_delta
        sta scroll_lo
        sta scroll_nt
        sta last_col_cam
        sta gen_run
        sta gen_step
        sta gen_kind
        sta col_ready

        lda #<SPEED_START
        sta speed_lo
        lda #>SPEED_START
        sta speed_hi
        lda #SPEED_RAMP
        sta ramp_timer

        lda #COL_AHEAD
        sta col_target

        ldx #NUM_OBST - 1
        lda #OB_NONE
@clear:
        sta obst_kind,x
        dex
        bpl @clear

        jsr pick_next               ; choose the first one the usual way...
        lda #34                     ; ...behind a longer run of clear ground
        sta gen_gap
        rts

; ---------------------------------------------------------------------------
;  One frame of world.  Order matters: the camera moves, everything already
;  out there moves with it, and only then is new ground invented -- so a
;  cactus spawned this frame is placed against the camera that drew it.
; ---------------------------------------------------------------------------
world_update:
        jsr world_advance
        jsr world_ramp_speed
        jsr world_move_obstacles

        lda cam_lo
        and #$F8
        cmp last_col_cam
        beq @done
        sta last_col_cam
        jsr gen_column
        lda col_target
        clc
        adc #1
        and #$3F
        sta col_target
@done:
        rts

; ---------------------------------------------------------------------------
;  cam += speed, and remember the whole pixels of it for everything else
; ---------------------------------------------------------------------------
world_advance:
        lda cam_lo
        sta tmp+0
        lda cam_frac
        clc
        adc speed_lo
        sta cam_frac
        lda cam_lo
        adc speed_hi
        sta cam_lo
        lda cam_hi
        adc #0
        sta cam_hi

        lda cam_lo
        sec
        sbc tmp+0
        sta cam_delta

        lda cam_lo
        sta scroll_lo
        lda cam_hi
        and #$01
        sta scroll_nt
        rts

; ---------------------------------------------------------------------------
;  A 256th of a pixel per frame faster, every eight frames, up to the cap.
;  Two minutes from a stroll to the fastest it ever gets.
; ---------------------------------------------------------------------------
world_ramp_speed:
        dec ramp_timer
        bne @done
        lda #SPEED_RAMP
        sta ramp_timer
        lda speed_hi
        cmp #>SPEED_MAX
        bcc @bump
        bne @done
        lda speed_lo
        cmp #<SPEED_MAX
        bcs @done
@bump:
        inc speed_lo
        bne @done
        inc speed_hi
@done:
        rts

; ---------------------------------------------------------------------------
;  Walk the live cacti left with the ground, and forget the ones that have
;  gone past the left edge.
; ---------------------------------------------------------------------------
world_move_obstacles:
        ldx #0
@loop:
        lda obst_kind,x
        beq @next

        lda obst_x_lo,x
        sec
        sbc cam_delta
        sta obst_x_lo,x
        lda obst_x_hi,x
        sbc #0
        sta obst_x_hi,x

        ldy obst_kind,x
        lda obst_width_px,y
        clc
        adc obst_x_lo,x
        sta tmp+0
        lda obst_x_hi,x
        adc #0
        cmp #>POS_BIAS
        bcc @retire
        bne @next
        lda tmp+0
        cmp #<POS_BIAS
        bcs @next
@retire:
        lda #OB_NONE
        sta obst_kind,x
@next:
        inx
        cpx #NUM_OBST
        bne @loop
        rts

; ---------------------------------------------------------------------------
;  Invent one column of world into col_buf: the horizon and whatever cactus
;  is standing in front of it, the ground line itself, and a row of grit under
;  that.  The rows below it are solid sand and never change, so they are drawn
;  once and left alone.
; ---------------------------------------------------------------------------
gen_column:
        jsr gen_mountain_column     ; the range, rows 17..23

        jsr rand
        and #$07                    ; six columns in eight are plain line
        cmp #6
        bcc @plain
        sec
        sbc #4                      ; 6 and 7 become GROUND_C and GROUND_D
        clc
        adc #GROUND_A
        jmp @put_ground
@plain:
        lda #GROUND_A
@put_ground:
        sta col_buf + MTN_ROWS

        jsr rand
        and #$07                    ; grit in one column of eight, no more
        cmp #2
        bcs @no_grit
        clc
        adc #GRIT_A
        sta col_buf + MTN_ROWS + 1
        jmp @obstacle
@no_grit:
        lda #SOLID_FILL
        sta col_buf + MTN_ROWS + 1

@obstacle:
        lda gen_run
        bne @emit

        dec gen_gap
        bne @done
        jsr start_obstacle
        bcc @try_again              ; nowhere to put it, so draw none
@emit:
        jsr emit_obstacle_column
        dec gen_run
        bne @done
        jsr pick_next
        jmp @done
@try_again:
        jsr pick_next
@done:
        lda #1
        sta col_ready
        rts

; ---------------------------------------------------------------------------
;  Three tiles of cactus for the column being drawn, written over whatever
;  the range had put in those rows.  A small one is the same column however
;  many are bunched together; a large one alternates its two.
; ---------------------------------------------------------------------------
emit_obstacle_column:
        lda gen_kind
        cmp #OB_PTERO
        beq @step                   ; a bird needs the room but draws nothing
        cmp #OB_LARGE1
        bcs @large

        lda #CACTUS_SMALL + 0
        sta col_buf + COL_CACTUS + 1
        lda #CACTUS_SMALL + 1
        sta col_buf + COL_CACTUS + 2
        jmp @step
@large:
        lda gen_step
        and #$01
        bne @right
        lda #CACTUS_LARGE + 0
        sta col_buf + COL_CACTUS + 0
        lda #CACTUS_LARGE + 2
        sta col_buf + COL_CACTUS + 1
        lda #CACTUS_LARGE + 4
        sta col_buf + COL_CACTUS + 2
        jmp @step
@right:
        lda #CACTUS_LARGE + 1
        sta col_buf + COL_CACTUS + 0
        lda #CACTUS_LARGE + 3
        sta col_buf + COL_CACTUS + 1
        lda #CACTUS_LARGE + 5
        sta col_buf + COL_CACTUS + 2
@step:
        inc gen_step
        rts

; ---------------------------------------------------------------------------
;  Start whatever pick_next settled on last time.  Carry set if it went out.
; ---------------------------------------------------------------------------
start_obstacle:
        lda gen_next
        cmp #OB_NONE                ; nothing due: wait out another gap
        bne @something
        clc
        rts
@something:
        cmp #OB_PTERO
        bne @begin
        lda ptero_on                ; one bird at a time; a cactus otherwise
        beq @begin
        lda #OB_SMALL1
        sta gen_next
@begin:
        lda gen_next
        sta gen_kind
        tax
        lda obst_width_cols,x
        sta gen_run
        lda #0
        sta gen_step
        lda gen_kind
        cmp #OB_PTERO
        beq @bird
        jmp spawn_obstacle
@bird:
        jsr ptero_spawn
        sec
        rts

; ---------------------------------------------------------------------------
;  Decide what is coming after this, and how much clear ground to leave in
;  front of it.  Both at once, because a bird needs more room than a cactus.
; ---------------------------------------------------------------------------
pick_next:
.ifdef DEBUG_NOCACTUS
        ; The birds-only build: never a cactus, so nothing but a bird can end
        ; a run.  When one is not allowed yet, nothing is due at all.
        lda #OB_PTERO
        sta gen_next
        lda hundreds
        cmp #PTERO_AFTER
        bcc @nothing
        lda ptero_on
        beq @gap
@nothing:
        lda #OB_NONE
        sta gen_next
        jmp @gap
.else
        jsr rand
        and #$07
        tax
        lda obst_choice,x
        sta gen_next
        cmp #OB_PTERO
        bne @gap

        lda hundreds                ; no birds until the score is up
        cmp #PTERO_AFTER
        bcc @cactus
        lda ptero_on                ; nor while one is still up there
        beq @gap
@cactus:
        lda #OB_SMALL1
        sta gen_next
.endif
@gap:
        jsr pick_gap
        lda gen_next
        cmp #OB_PTERO
        bne @done
        lda gen_gap
        clc
        adc #PTERO_LEAD
        sta gen_gap
@done:
        rts

spawn_obstacle:
        ldx #0
@find:
        lda obst_kind,x
        beq @free
        inx
        cpx #NUM_OBST
        bne @find
        lda #0
        sta gen_run                 ; no slot: pretend it was never chosen
        clc
        rts
@free:
        lda gen_kind
        sta obst_kind,x
        lda cam_lo
        and #$07
        sta tmp+0
        lda #<(SPAWN_X + POS_BIAS)
        sec
        sbc tmp+0
        sta obst_x_lo,x
        lda #>(SPAWN_X + POS_BIAS)
        sbc #0
        sta obst_x_hi,x
        sec
        rts

; ---------------------------------------------------------------------------
;  How much clear ground before the next one.  It grows with the speed,
;  because the room to react has to stay roughly constant in time rather
;  than in pixels.
; ---------------------------------------------------------------------------
pick_gap:
        jsr rand
        and #$0F
        sta tmp+0
        lda speed_hi
        asl a
        clc
        adc speed_hi                ; three columns a whole pixel of speed
        clc
        adc #12
        clc
        adc tmp+0
        sta gen_gap
        rts

; ---------------------------------------------------------------------------
;  Did the dino just run into something?  Carry set if it did.
; ---------------------------------------------------------------------------
;  Everything x is biased by POS_BIAS, so the dino's own box -- which never
;  moves -- is simply its screen position with a high byte of 2.
; ---------------------------------------------------------------------------
check_obstacles:
        lda #DINO_X + HIT_L
        sta tmp+0
        lda #>POS_BIAS
        sta tmp+1
        sta tmp+3

        lda dino_state
        cmp #2
        bne @standing
        lda #DINO_X + HIT_R_DUCK
        ldy #DUCK_H
        bne @have
@standing:
        lda #DINO_X + HIT_R
        ldy #DINO_H
@have:
        sta tmp+2
        sty tmp+4

        ldx #0
@loop:
        ldy obst_kind,x
        beq @next

        lda obst_hit_l,y
        clc
        adc obst_x_lo,x
        sta tmp+5
        lda obst_x_hi,x
        adc #0
        sta tmp+6

        ; left edge of the cactus against the dino's right edge
        lda tmp+6
        cmp tmp+3
        bcc @maybe
        bne @next
        lda tmp+5
        cmp tmp+2
        bcs @next
@maybe:
        ; right edge of the cactus against the dino's left edge
        lda obst_hit_w,y
        clc
        adc tmp+5
        sta tmp+5
        lda tmp+6
        adc #0
        sta tmp+6

        lda tmp+1
        cmp tmp+6
        bcc @overlap
        bne @next
        lda tmp+0
        cmp tmp+5
        bcs @next
@overlap:
        ; horizontally on top of it; is the dino low enough to touch it?
        lda dino_y
        clc
        adc tmp+4
        cmp obst_hit_t,y
        beq @next
        bcs @hit
@next:
        inx
        cpx #NUM_OBST
        bne @loop
        clc
        rts
@hit:
        sec
        rts
