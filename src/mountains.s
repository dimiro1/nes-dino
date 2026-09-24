; ===========================================================================
;  mountains.s -- the range along the horizon
; ===========================================================================
;  Scenery, and nothing else: nothing can hit a mountain, and it has a
;  generator of its own quite apart from the one that places cacti.  The two
;  write different rows of the same column, and where they do meet -- the
;  outer corner of a slope, where a cactus happens to stand -- the cactus is
;  written second and wins, which is the right way round.
;
;  A mountain is an open triangle, the way Super Mario Land draws one: two
;  forty-five degree slopes and nothing in between, so the sky shows through
;  it and the dino runs in front of it.  That also means there is no shape to
;  store anywhere.  A mountain h rows high is 2h columns wide, and the single
;  tile of slope in column s of it sits s rows up from the bottom on the way
;  up and 2h-1-s rows up on the way down; every other row of the column is
;  sky.  The bottom row is always row 23, the last one above the ground line,
;  so a tall one and a low one stand on the same horizon and both of them
;  reach right down to it.
; ===========================================================================

MTN_TALL      = MTN_ROWS           ; reaches row 17, and is 14 columns wide
MTN_LOW       = 4                  ; reaches row 20, and is 8

.segment "CODE"

mtn_init:
        lda #0
        sta mtn_run
        sta mtn_step
        lda #3                      ; a little clear horizon to open with
        sta mtn_gap
        rts

; ---------------------------------------------------------------------------
;  One column of horizon into col_buf, rows 17..23.  Called before the cacti
;  go in, so that theirs is the tile that survives.
; ---------------------------------------------------------------------------
gen_mountain_column:
        ldy #MTN_ROWS - 1           ; clear sky first: a column holds one tile
        lda #BG_BLANK               ; of slope at most, and usually none
@sky:
        sta col_buf,y
        dey
        bpl @sky

        lda mtn_run
        bne @slope
        dec mtn_gap
        bne @done
        jsr pick_mountain

@slope:
        lda mtn_step
        cmp mtn_height
        bcs @falling
        ldx #MTN_LEFT               ; the near side, climbing
        jmp @rows
@falling:
        ldx #MTN_RIGHT
        lda mtn_height
        asl a
        sec
        sbc #1
        sbc mtn_step                ; 2h-1-s: as far back from the far corner
@rows:
        sta tmp+0                   ; rows up from the foot of the range
        lda #MTN_ROWS - 1
        sec
        sbc tmp+0
        tay
        txa
        sta col_buf,y

        inc mtn_step
        dec mtn_run
        bne @done
        jsr rand                    ; how much clear horizon comes after it
        and #$0F
        clc
        adc #1                      ; ...which may be none, and two peaks
        sta mtn_gap                 ;    then meet in a valley
@done:
        rts

; ---------------------------------------------------------------------------
;  A tall one or a low one, evenly.  Either is twice as wide as it is high,
;  because both of its sides are the same forty-five degree slope.
; ---------------------------------------------------------------------------
pick_mountain:
        jsr rand
        and #$01
        beq @low
        lda #MTN_TALL
        bne @set                    ; always
@low:
        lda #MTN_LOW
@set:
        sta mtn_height
        asl a
        sta mtn_run
        lda #0
        sta mtn_step
        rts
