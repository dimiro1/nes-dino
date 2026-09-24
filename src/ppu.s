; ===========================================================================
;  ppu.s -- everything that talks to the picture chip
; ===========================================================================
;  Nothing outside the NMI writes to the PPU while it is drawing.  The main
;  loop instead leaves commands in ppu_queue:
;
;      addr hi, addr lo, count | $80 for a down-the-column write, data...
;
;  terminated by a zero, which no nametable or palette address ever starts
;  with.  The NMI plays the whole queue back in vblank.
; ===========================================================================

.segment "CODE"

; ---------------------------------------------------------------------------
;  Play the queue into the PPU.  Called from the NMI only.
; ---------------------------------------------------------------------------
ppu_flush_queue:
        ldx #0
@next:
        lda ppu_queue,x
        beq @done
        sta nmi_tmp+0               ; address, held until the mode is set
        inx
        lda ppu_queue,x
        sta nmi_tmp+1
        inx
        lda ppu_queue,x
        inx
        tay                         ; count and its direction flag
        and #$80
        beq @across
        lda ppu_ctrl
        ora #$04                    ; step 32: straight down a column
        bne @mode                   ; ppu_ctrl always has bit 7 set
@across:
        lda ppu_ctrl                ; step 1: along a row
@mode:
        sta PPUCTRL
        lda nmi_tmp+0
        sta PPUADDR
        lda nmi_tmp+1
        sta PPUADDR
        tya
        and #$7F
        tay
@copy:
        lda ppu_queue,x
        sta PPUDATA
        inx
        dey
        bne @copy
        beq @next                   ; always
@done:
        rts

; ---------------------------------------------------------------------------
;  Building a command.  q_cmd writes the header, q_push each byte after it.
;  in: A = address hi, X = address lo, q_count = count (bit 7 steps by 32)
; ---------------------------------------------------------------------------
q_cmd:
        stx tmp+3
        ldx queue_len
        sta ppu_queue,x
        inx
        lda tmp+3
        sta ppu_queue,x
        inx
        lda q_count
        sta ppu_queue,x
        inx
        stx queue_len
        rts

q_push:
        ldx queue_len
        sta ppu_queue,x
        inx
        stx queue_len
        rts

queue_terminate:
        ldx queue_len
        lda #0
        sta ppu_queue,x
        rts

; ---------------------------------------------------------------------------
;  Where a screen column currently lives in the nametables.  The world is 64
;  columns wide and wraps, so this is the only place the two nametables are
;  ever told apart.
; ---------------------------------------------------------------------------
calc_nt_base:
        lda cam_lo
        lsr a
        lsr a
        lsr a
        sta nt_col_base
        lda cam_hi
        and #$01
        beq @done
        lda nt_col_base
        ora #$20
        sta nt_col_base
@done:
        rts

; in:  A = screen column 0..31, tmp+0 = nametable row
; out: A = address hi, X = address lo.  Y is untouched.
calc_nt_addr:
        clc
        adc nt_col_base
        and #$3F
        cmp #32
        bcc @nt0
        sec
        sbc #32
        sta tmp+1
        lda #$24
        bne @base
@nt0:
        sta tmp+1
        lda #$20
@base:
        sta tmp+2
        lda tmp+0
        lsr a
        lsr a
        lsr a
        clc
        adc tmp+2
        sta tmp+2                   ; hi, once the row's high bits are in
        lda tmp+0
        and #$07
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc tmp+1
        tax
        lda tmp+2
        rts

; ---------------------------------------------------------------------------
;  Queue a string, one character a command, because a run of them can cross
;  from one nametable into the other.  ptr points at the text; txt_row,
;  txt_col and txt_len say where it goes and how long it is.
; ---------------------------------------------------------------------------
queue_text:
        jsr calc_nt_base
        lda txt_row
        sta tmp+0
        ldy #0
@loop:
        cpy txt_len
        beq @done
        tya
        clc
        adc txt_col
        jsr calc_nt_addr
        sty tmp+4
        ldy #1
        sty q_count
        jsr q_cmd
        ldy tmp+4
        lda (ptr),y
        jsr q_push
        iny
        bne @loop
@done:
        rts

; ---------------------------------------------------------------------------
;  The same, with one tile repeated -- which is how a message is rubbed out.
;  in: A = tile
; ---------------------------------------------------------------------------
queue_fill:
        sta tmp+5
        jsr calc_nt_base
        lda txt_row
        sta tmp+0
        ldy #0
@loop:
        cpy txt_len
        beq @done
        tya
        clc
        adc txt_col
        jsr calc_nt_addr
        sty tmp+4
        ldy #1
        sty q_count
        jsr q_cmd
        lda tmp+5
        jsr q_push
        ldy tmp+4
        iny
        bne @loop
@done:
        rts

; ---------------------------------------------------------------------------
;  The per-frame queue: a new column of world, the score if it moved, and the
;  palette if day just turned into night.
; ---------------------------------------------------------------------------
queue_frame_work:
        lda col_ready
        beq @no_column
        jsr queue_column
        lda #0
        sta col_ready
@no_column:
        lda score_dirty
        beq @no_score
        jsr queue_score
        lda #0
        sta score_dirty
@no_score:
        lda pal_dirty
        beq @no_palette
        jsr queue_palette
        lda #0
        sta pal_dirty
@no_palette:
        rts

; ---------------------------------------------------------------------------
;  The new column of ground, written downwards through rows 21..25.
; ---------------------------------------------------------------------------
queue_column:
        lda col_target
        cmp #32
        bcc @nt0
        sec
        sbc #32
        clc
        adc #<($26A0)
        tax
        lda #>($26A0)
        bne @go
@nt0:
        clc
        adc #<($22A0)
        tax
        lda #>($22A0)
@go:
        ldy #COL_ROWS | $80         ; step 32, so this walks down the column
        sty q_count
        jsr q_cmd
        ldy #0
@copy:
        lda col_buf,y
        jsr q_push
        iny
        cpy #COL_ROWS
        bne @copy
        rts

; ---------------------------------------------------------------------------
;  The score bar.  Both numbers live in nametable 0 row 2, which the split
;  keeps still while the world slides past underneath.
; ---------------------------------------------------------------------------
queue_score:
        ; Every hundred points the number blinks three times.  flash_timer
        ; counts the frames down and its bit 3 is which half of each blink
        ; this frame is in.
        lda #0
        sta tmp+6
        lda flash_timer
        beq @ready
        and #$08
        beq @ready
        inc tmp+6
@ready:
        lda #5
        sta q_count
        ldx #<($205A)
        lda #>($205A)
        jsr q_cmd
        ldy #0
@cur:
        lda tmp+6
        bne @gap
        lda score,y
        clc
        adc #DIGIT_0
        jmp @put
@gap:
        lda #BG_BLANK
@put:
        jsr q_push
        iny
        cpy #5
        bne @cur

        lda #5
        sta q_count
        ldx #<($2053)
        lda #>($2053)
        jsr q_cmd
        ldy #0
@hi:
        lda hi_score,y
        clc
        adc #DIGIT_0
        jsr q_push
        iny
        cpy #5
        bne @hi
        rts

; ---------------------------------------------------------------------------
;  Day or night.  Four background colours and four sprite ones; the sprite
;  set's first entry is a mirror of the backdrop, so writing it changes
;  nothing and keeps the loop simple.
; ---------------------------------------------------------------------------
queue_palette:
        lda night
        beq @day
        lda #<palette_night
        sta ptr
        lda #>palette_night
        sta ptr+1
        bne @write
@day:
        lda #<palette_day
        sta ptr
        lda #>palette_day
        sta ptr+1
@write:
        lda #4
        sta q_count
        ldx #<($3F00)
        lda #>($3F00)
        jsr q_cmd
        ldy #0
@bg:
        lda (ptr),y
        jsr q_push
        iny
        cpy #4
        bne @bg

        lda #4
        sta q_count
        ldx #<($3F10)
        lda #>($3F10)
        jsr q_cmd
        ldy #4
@spr:
        lda (ptr),y
        jsr q_push
        iny
        cpy #8
        bne @spr
        rts

; ===========================================================================
;  Drawing the first screen, with the beam switched off and all the time in
;  the world.  Everything here writes the PPU directly.
; ===========================================================================
ppu_draw_first_screen:
        ; --- palette ---------------------------------------------------
        bit PPUSTATUS
        lda #$3F
        sta PPUADDR
        lda #$00
        sta PPUADDR
        ldx #0
@pal:
        lda palette_day,x
        sta PPUDATA
        inx
        cpx #4
        bne @pal
        ; the other three background sets and all four sprite sets are the
        ; same four colours, so nothing on screen can pick a wrong one
        ldy #7
@palrest:
        ldx #0
@palrest_inner:
        lda palette_day,x
        sta PPUDATA
        inx
        cpx #4
        bne @palrest_inner
        dey
        bne @palrest

        ; --- both nametables and both attribute tables, wiped ----------
        ; The game is monochrome, so every palette is the same four colours
        ; and the attribute tables can stay zero for the whole run -- which
        ; is why no scrolled column ever has to carry attribute bytes with it.
        lda #$20
        sta PPUADDR
        lda #$00
        sta PPUADDR
        lda #BG_BLANK
        ldx #8                      ; 8 x 256 bytes covers $2000..$27FF
        ldy #0
@wipe:
        sta PPUDATA
        iny
        bne @wipe
        dex
        bne @wipe

        ; --- the ground line, straight across both nametables ----------
        lda #>($2300)
        ldx #<($2300)
        jsr draw_ground_row
        lda #>($2700)
        ldx #<($2700)
        jsr draw_ground_row
        lda #>($2320)
        ldx #<($2320)
        jsr draw_grit_row
        lda #>($2720)
        ldx #<($2720)
        jsr draw_grit_row

        ; --- the score bar ---------------------------------------------
        lda #>($2041)
        ldx #<($2041)
        jsr ppu_set_addr
        lda #BG_SPR0_PAD            ; opaque, invisible, and what sprite 0 hits
        sta PPUDATA

        lda #>($2050)
        ldx #<($2050)
        jsr ppu_set_addr
        lda #LETTER_H
        sta PPUDATA
        lda #LETTER_I
        sta PPUDATA

        lda #>($2053)
        ldx #<($2053)
        jsr ppu_set_addr
        ldx #5
@hi:
        lda #DIGIT_0
        sta PPUDATA
        dex
        bne @hi

        lda #>($205A)
        ldx #<($205A)
        jsr ppu_set_addr
        ldx #5
@cur:
        lda #DIGIT_0
        sta PPUDATA
        dex
        bne @cur

        ; PRESS START, row 12 column 10.  The camera has not moved yet, so
        ; this lands in nametable 0 where state_ready can rub it out again.
        lda #>($218A)
        ldx #<($218A)
        jsr ppu_set_addr
        ldy #0
@prompt:
        lda txt_press_start,y
        sta PPUDATA
        iny
        cpy #11
        bne @prompt
        rts

draw_ground_row:
        jsr ppu_set_addr
        ldx #32
@loop:
        jsr rand
        and #$07
        cmp #6
        bcc @plain
        sec
        sbc #4
        clc
        adc #GROUND_A
        jmp @put
@plain:
        lda #GROUND_A
@put:
        sta PPUDATA
        dex
        bne @loop
        rts

draw_grit_row:
        jsr ppu_set_addr
        ldx #32
@loop:
        jsr rand
        and #$07
        cmp #2
        bcc @some
        lda #BG_BLANK
        bne @put
@some:
        clc
        adc #GRIT_A
@put:
        sta PPUDATA
        dex
        bne @loop
        rts

; in: A = address hi, X = address lo
ppu_set_addr:
        bit PPUSTATUS
        sta PPUADDR
        stx PPUADDR
        rts
