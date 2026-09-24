; ===========================================================================
;  ptero.s -- the pterodactyl
; ===========================================================================
;  It flies right to left a little faster than the ground moves, at one of
;  three heights.  The low one has to be jumped, the middle one ducked (or
;  jumped), and the high one can be run straight under -- it only ever
;  catches a dino that jumped into it.
;
;  When one appears is not decided here: a bird is one of the things the
;  obstacle generator in world.s can choose, so it takes its turn in the same
;  queue as the cacti and obeys the same rules about the clear ground either
;  side of it.  Deciding separately is what used to let a bird arrive on top
;  of a cactus, which is a pair nothing can get through.
; ===========================================================================

.segment "CODE"

ptero_init:
        lda #0
        sta ptero_on
        sta ptero_anim
        lda #8
        sta ptero_timer
        rts

ptero_update:
        lda ptero_on
        bne @fly
        rts

@fly:
        lda ptero_x_lo
        sec
        sbc cam_delta
        sta ptero_x_lo
        lda ptero_x_hi
        sbc #0
        sta ptero_x_hi

        lda ptero_x_lo              ; and its own headwind on top
        sec
        sbc #PTERO_DRIFT
        sta ptero_x_lo
        lda ptero_x_hi
        sbc #0
        sta ptero_x_hi

        lda ptero_x_lo
        clc
        adc #PTERO_W
        sta tmp+0
        lda ptero_x_hi
        adc #0
        cmp #>POS_BIAS
        bcc @gone
        bne @flap
        lda tmp+0
        cmp #<POS_BIAS
        bcs @flap
@gone:
        lda #0
        sta ptero_on
        rts

@flap:
        dec ptero_timer
        bne @done
        lda #8
        sta ptero_timer
        lda ptero_anim
        eor #$01
        sta ptero_anim
@done:
        rts

ptero_spawn:
        lda #1
        sta ptero_on
        lda #<(SPAWN_X + POS_BIAS)
        sta ptero_x_lo
        lda #>(SPAWN_X + POS_BIAS)
        sta ptero_x_hi
        jsr rand
        and #$03
        tax
        lda ptero_heights,x
        sta ptero_y
        lda #0
        sta ptero_anim
        lda #8
        sta ptero_timer
        rts

; ---------------------------------------------------------------------------
;  Did the dino fly into the bird?  Carry set if so.  Unlike a cactus this
;  needs a real test at both top and bottom, since the whole point of the
;  high ones is that there is room underneath.
; ---------------------------------------------------------------------------
check_ptero:
        lda ptero_on
        bne @test
        clc
        rts
@test:
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

        ; the bird's box, inset two pixels from the drawing all round
        lda ptero_x_lo
        clc
        adc #2
        sta tmp+5
        lda ptero_x_hi
        adc #0
        sta tmp+6

        lda tmp+6                   ; bird's left vs dino's right
        cmp tmp+3
        bcc @maybe
        bne @miss
        lda tmp+5
        cmp tmp+2
        bcs @miss
@maybe:
        lda #PTERO_W - 4            ; bird's right vs dino's left
        clc
        adc tmp+5
        sta tmp+5
        lda tmp+6
        adc #0
        sta tmp+6

        lda tmp+1
        cmp tmp+6
        bcc @across
        bne @miss
        lda tmp+0
        cmp tmp+5
        bcs @miss
@across:
        ; dino top < bird bottom, and bird top < dino bottom
        lda dino_y
        clc
        adc #HIT_T
        sta tmp+7                   ; dino top
        lda ptero_y
        clc
        adc #PTERO_H - 2
        cmp tmp+7
        bcc @miss                   ; bird's bottom is above the dino
        beq @miss

        lda dino_y
        clc
        adc tmp+4
        sta tmp+7                   ; dino bottom
        lda ptero_y
        clc
        adc #2
        cmp tmp+7
        bcs @miss                   ; bird's top is below the dino
        sec
        rts
@miss:
        clc
        rts
