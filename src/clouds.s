; ===========================================================================
;  clouds.s -- the sky
; ===========================================================================
;  Clouds are sprites rather than background tiles, which is what lets them
;  drift at a quarter of the ground's speed and give the screen some depth.
;
;  Each one keeps to a band of scanlines of its own, so that three of them,
;  three tiles wide, can never put more than three sprites on any one line.
;  Every band also finishes well above the highest a bird ever flies, so a
;  cloud and a bird cannot land on one line either.
;
;  Sideways, they all move at one speed -- which means they keep whatever
;  spacing they first fell into, and a sky that bunched up once would stay
;  bunched for the rest of the run.  So a cloud coming back round is not
;  dropped just beyond the right edge, but a random gap past whichever cloud
;  is furthest out: the same way the ground spaces its cacti, and for the
;  same reason.
; ===========================================================================

CLOUD_GAP = 64                      ; the least room left between two of them

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
        jsr cloud_respawn
@next:
        inx
        cpx #NUM_CLOUDS
        bne @loop
        rts

; ---------------------------------------------------------------------------
;  Cloud X, back round the other side: a gap of 64 to 191 pixels behind the
;  furthest-out cloud there is, and a fresh line inside its own band.
; ---------------------------------------------------------------------------
cloud_respawn:
        jsr clouds_rightmost
        jsr rand
        and #$7F
        clc
        adc #CLOUD_GAP              ; at most $BF, so this cannot carry...
        clc
        adc tmp+2                   ; ...and only this one can
        sta cloud_x_lo,x
        lda tmp+3
        adc #0
        sta cloud_x_hi,x
        lda #0
        sta cloud_frac,x

        jsr rand
        and #$0F
        clc
        adc cloud_base_y,x
        sta cloud_y,x
        rts

; ---------------------------------------------------------------------------
;  Where the furthest-out cloud has got to, in tmp+2 and tmp+3 -- or the right
;  edge of the screen if all of them are inside it, so that a cloud can never
;  be put back in front of the player rather than beyond him.  A cloud that
;  has already gone off the left, which includes the one being moved, is not
;  a candidate: its x is negative.
; ---------------------------------------------------------------------------
clouds_rightmost:
        lda #<256
        sta tmp+2
        lda #>256
        sta tmp+3
        ldy #0
@loop:
        lda cloud_x_hi,y
        bmi @next
        cmp tmp+3
        bcc @next
        bne @take
        lda cloud_x_lo,y
        cmp tmp+2
        bcc @next
@take:
        lda cloud_x_lo,y
        sta tmp+2
        lda cloud_x_hi,y
        sta tmp+3
@next:
        iny
        cpy #NUM_CLOUDS
        bne @loop
        rts
