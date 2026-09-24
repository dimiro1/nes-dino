; ===========================================================================
;  clouds.s -- the sky
; ===========================================================================
;  Clouds are sprites rather than background tiles, which is what lets them
;  drift at a quarter of the ground's speed and give the screen some depth.
;  Each one keeps to its own band of scanlines so that three of them, three
;  tiles wide, can never put more than three sprites on any one line.
; ===========================================================================

.segment "CODE"

clouds_init:
        ldx #0
@loop:
        lda cloud_start_x,x
        sta cloud_x_lo,x
        lda #0
        sta cloud_x_hi,x
        sta cloud_frac,x
        lda cloud_base_y,x
        sta cloud_y,x
        inx
        cpx #NUM_CLOUDS
        bne @loop
        rts

clouds_update:
        lda speed_hi                ; a quarter of the camera's speed
        lsr a
        sta tmp+1
        lda speed_lo
        ror a
        sta tmp+0
        lsr tmp+1
        ror tmp+0

        ldx #0
@loop:
        lda cloud_frac,x
        sec
        sbc tmp+0
        sta cloud_frac,x
        lda cloud_x_lo,x
        sbc tmp+1
        sta cloud_x_lo,x
        lda cloud_x_hi,x
        sbc #0
        sta cloud_x_hi,x

        lda cloud_x_lo,x            ; wholly past the left edge?
        clc
        adc #CLOUD_W
        lda cloud_x_hi,x
        adc #0
        bpl @next

        jsr rand                    ; back round the other side
        and #$3F
        sta cloud_x_lo,x
        lda #1
        sta cloud_x_hi,x
        lda #0
        sta cloud_frac,x
        jsr rand
        and #$07
        clc
        adc cloud_base_y,x
        sta cloud_y,x
@next:
        inx
        cpx #NUM_CLOUDS
        bne @loop
        rts
