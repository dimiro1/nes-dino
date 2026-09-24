; ===========================================================================
;  score.s -- distance, in points
; ===========================================================================
;  One point every sixteen pixels of ground.  Every hundred of them rings a
;  bell and flashes the number, and every seventh hundred turns the world
;  from day to night by rewriting four colours.
; ===========================================================================

.segment "CODE"

score_init:
        ldx #4
        lda #0
@loop:
        sta score,x
        dex
        bpl @loop
        sta dist_acc
        sta hundreds
        sta flash_timer
        lda #1
        sta score_dirty
        rts

score_clear_hi:
        ldx #4
        lda #0
@loop:
        sta hi_score,x
        dex
        bpl @loop
        rts

score_update:
        lda dist_acc
        clc
        adc cam_delta
        sta dist_acc
@spend:
        cmp #DIST_PER_POINT
        bcc @flash
        sec
        sbc #DIST_PER_POINT
        sta dist_acc
        jsr score_inc
        lda dist_acc
        jmp @spend

@flash:
        lda flash_timer
        beq @done
        dec flash_timer
        lda flash_timer
        and #$07                    ; on and off every eight frames
        bne @done
        lda #1
        sta score_dirty
@done:
        rts

; ---------------------------------------------------------------------------
;  Add one, digit by digit from the units up.  A carry reaching the hundreds
;  is what a milestone is.
; ---------------------------------------------------------------------------
score_inc:
        ldx #4
@loop:
        inc score,x
        lda score,x
        cmp #10
        bcc @done
        lda #0
        sta score,x
        dex
        bmi @peg
        cpx #2
        bne @loop
        jsr score_milestone
        jmp @loop
@peg:
        ldx #4                      ; 99999 and no further
        lda #9
@pegloop:
        sta score,x
        dex
        bpl @pegloop
@done:
        lda #1
        sta score_dirty
        rts

score_milestone:
        inc hundreds
        lda #SFX_POINT
        jsr sound_play
        lda #48
        sta flash_timer

        inc night_count
        lda night_count
        cmp #NIGHT_EVERY
        bcc @done
        lda #0
        sta night_count
        lda night
        eor #$01
        sta night
        lda #1
        sta pal_dirty
@done:
        rts

; ---------------------------------------------------------------------------
;  Beaten the best?  Compared most significant digit first, so the first
;  difference decides it.
; ---------------------------------------------------------------------------
score_check_hi:
        ldx #0
@loop:
        lda score,x
        cmp hi_score,x
        bcc @done
        bne @copy
        inx
        cpx #5
        bne @loop
        rts
@copy:
        ldx #0
@cp:
        lda score,x
        sta hi_score,x
        inx
        cpx #5
        bne @cp
        lda #1
        sta score_dirty
@done:
        rts
