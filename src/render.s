; ===========================================================================
;  render.s -- filling the OAM buffer
; ===========================================================================
;  Sprite 0 first, because the split depends on it being slot zero, then the
;  dino, the bird and the clouds.  Nothing here ever puts more than seven
;  sprites on one scanline, so the hardware never has to drop any.
; ===========================================================================

.segment "CODE"

build_oam:
        lda #SPR0_Y
        sta oam+0
        lda #SPR0_MARK
        sta oam+1
        lda #0
        sta oam+2
        lda #SPR0_X
        sta oam+3
        lda #1
        sta oam_idx

        jsr draw_dino
        jsr draw_ptero
        jsr draw_clouds

        ; park whatever is left below the bottom of the screen
        lda oam_idx
        asl a
        asl a
        tax
        lda #$FF
@hide:
        sta oam,x
        inx
        inx
        inx
        inx
        bne @hide
        rts

; ---------------------------------------------------------------------------
;  Draw a block of tiles, row major from blit_tile, at a 16-bit signed x.
;  A tile that would fall off either edge is parked instead of wrapping,
;  which is what lets a cloud walk off the left of the screen cleanly.
; ---------------------------------------------------------------------------
draw_block:
        lda blit_tile
        sta tmp+5
        lda #0
        sta tmp+0                   ; tile row
@row:
        lda #0
        sta tmp+1                   ; tile column
@col:
        lda tmp+1
        asl a
        asl a
        asl a
        clc
        adc blit_x_lo
        sta tmp+2
        lda blit_x_hi
        adc #0
        bne @hide
        lda tmp+2
        cmp #249
        bcs @hide

        lda tmp+0
        asl a
        asl a
        asl a
        clc
        adc blit_y
        sec
        sbc #1                      ; OAM y is one line above the top
        sta tmp+3
        jmp @emit
@hide:
        lda #$FF
        sta tmp+3
@emit:
        lda oam_idx
        asl a
        asl a
        tax
        lda tmp+3
        sta oam+0,x
        lda tmp+5
        sta oam+1,x
        lda #0
        sta oam+2,x
        lda tmp+2
        sta oam+3,x

        inc oam_idx
        inc tmp+5
        inc tmp+1
        lda tmp+1
        cmp blit_w
        bne @col

        inc tmp+0
        lda tmp+0
        cmp blit_h
        bne @row
        rts

; ---------------------------------------------------------------------------
draw_dino:
        lda #DINO_X
        sta blit_x_lo
        lda #0
        sta blit_x_hi
        lda dino_y
        sta blit_y

        lda game_state
        cmp #ST_READY
        bne @playing
        lda frame_count             ; a blink every two seconds or so
        and #$7F
        cmp #$78
        bcc @idle
        lda #DINO_BLINK
        jmp @tall
@playing:

        lda dino_state
        cmp #3
        beq @dead
        cmp #2
        beq @duck
        cmp #1
        beq @idle                   ; one pose for the whole jump

        lda dino_anim
        beq @run1
        lda #DINO_RUN2
        jmp @tall
@run1:
        lda #DINO_RUN1
        jmp @tall
@idle:
        lda #DINO_STAND
        jmp @tall
@dead:
        lda #DINO_DEAD
@tall:
        sta blit_tile
        lda #3
        sta blit_w
        sta blit_h
        jmp draw_block

@duck:
        lda dino_anim
        beq @duck1
        lda #DINO_DUCK2
        jmp @wide
@duck1:
        lda #DINO_DUCK1
@wide:
        sta blit_tile
        lda #4
        sta blit_w
        lda #2
        sta blit_h
        jmp draw_block

; ---------------------------------------------------------------------------
draw_ptero:
        lda ptero_on
        bne @go
        rts
@go:
        lda ptero_x_lo
        sta blit_x_lo
        lda ptero_x_hi
        sec
        sbc #>POS_BIAS
        sta blit_x_hi
        lda ptero_y
        sta blit_y
        lda ptero_anim
        beq @up
        lda #PTERO_DOWN
        jmp @set
@up:
        lda #PTERO_UP
@set:
        sta blit_tile
        lda #3
        sta blit_w
        lda #2
        sta blit_h
        jmp draw_block

; ---------------------------------------------------------------------------
draw_clouds:
        ldx #0
        stx tmp+6
@loop:
        ldx tmp+6
        lda cloud_x_lo,x
        sta blit_x_lo
        lda cloud_x_hi,x
        sta blit_x_hi
        lda cloud_y,x
        sta blit_y
        lda #CLOUD
        sta blit_tile
        lda #3
        sta blit_w
        lda #1
        sta blit_h
        jsr draw_block
        inc tmp+6
        lda tmp+6
        cmp #NUM_CLOUDS
        bne @loop
        rts
