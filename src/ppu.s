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

; ===========================================================================
;  Writing along a nametable row
; ===========================================================================
;  Both of the routines below go out as runs rather than as a command each
;  character.  A command costs the flush four times what a byte of data does,
;  and rubbing out two whole lines one character at a time is more than a
;  vblank holds -- the tail of it would land while the beam was already
;  drawing, and leave half a word behind.
;
;  A run only ever has to break where the row crosses from one nametable into
;  the other.  tmp+6 counts the characters already written; queue_row_run
;  works out how many of the rest fit in one command, leaves that in tmp+7,
;  and writes the header.  Carry clear when there is nothing left to do.
; ---------------------------------------------------------------------------
queue_row_run:
        lda tmp+6
        cmp txt_len
        bcc @more
        clc
        rts
@more:
        clc
        adc txt_col
        clc
        adc nt_col_base
        and #$1F                    ; where in this nametable the run starts
        sta tmp+7
        lda #32
        sec
        sbc tmp+7                   ; ...so this much room before it crosses
        sta tmp+7
        lda txt_len
        sec
        sbc tmp+6                   ; and this much left to write
        cmp tmp+7
        bcc @fits
        lda tmp+7
@fits:
        sta tmp+7
        sta q_count
        lda tmp+6
        clc
        adc txt_col
        jsr calc_nt_addr
        jsr q_cmd
        sec
        rts

; ---------------------------------------------------------------------------
;  Queue a string.  ptr points at the text; txt_row, txt_col and txt_len say
;  where it goes and how long it is.
; ---------------------------------------------------------------------------
queue_text:
        jsr calc_nt_base
        lda txt_row
        sta tmp+0
        lda #0
        sta tmp+6
@run:
        jsr queue_row_run
        bcc @done
        lda tmp+7
        sta tmp+8
        ldy tmp+6
@copy:
        lda (ptr),y
        jsr q_push
        iny
        dec tmp+8
        bne @copy
        sty tmp+6
        jmp @run
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
        lda #0
        sta tmp+6
@run:
        jsr queue_row_run
        bcc @done
        ldy tmp+7
@copy:
        lda tmp+5
        jsr q_push
        dey
        bne @copy
        lda tmp+6
        clc
        adc tmp+7
        sta tmp+6
        jmp @run
@done:
        rts

; ---------------------------------------------------------------------------
;  The per-frame queue: a new column of world, the score if it moved, and the
;  palette if day just turned into night or the player just changed scheme.
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
;  The new column of world, written downwards through rows 17..25: the range,
;  the cactus standing in front of it, the ground line and the grit.
; ---------------------------------------------------------------------------
NT0_COLUMN = $2000 + ROW_COL_TOP * 32
NT1_COLUMN = $2400 + ROW_COL_TOP * 32

queue_column:
        lda col_target
        cmp #32
        bcc @nt0
        sec
        sbc #32
        clc
        adc #<NT1_COLUMN
        tax
        lda #>NT1_COLUMN
        bne @go
@nt0:
        clc
        adc #<NT0_COLUMN
        tax
        lda #>NT0_COLUMN
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

; ===========================================================================
;  Drawing the first screen, with the beam switched off and all the time in
;  the world.  Everything here writes the PPU directly.
; ===========================================================================
ppu_draw_first_screen:
        ; --- palette ---------------------------------------------------
        jsr pal_write_all

        ; --- both nametables and both attribute tables, wiped ----------
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

        ; --- which palette each band of the screen gets ----------------
        ; Written here and never again, even though the world scrolls under
        ; it: the reason is with attr_bands, and it is why no scrolled column
        ; ever has to carry attribute bytes with it.
        lda #>($23C0)
        ldx #<($23C0)
        jsr draw_attr_bands
        lda #>($27C0)
        ldx #<($27C0)
        jsr draw_attr_bands

        ; --- the ground, straight across both nametables ---------------
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
        lda #>($2340)
        ldx #<($2340)
        ldy #128
        jsr draw_solid_run
        lda #>($2740)
        ldx #<($2740)
        ldy #128
        jsr draw_solid_run

        ; --- the range along the horizon -------------------------------
        ; Only as far as the first column the scroller will write.  Past
        ; that the two would be inventing the same ground twice over and
        ; would not agree about it; and everything past it is written by the
        ; scroller long before the camera arrives.
        lda #>NT0_COLUMN
        ldx #<NT0_COLUMN
        ldy #32
        jsr draw_mountain_cols
        lda #>NT1_COLUMN
        ldx #<NT1_COLUMN
        ldy #COL_AHEAD + 1 - 32
        jsr draw_mountain_cols

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

        ; ...and under it the button nobody would otherwise find, followed by
        ; the name of the scheme it is on.  The name is on the same row and
        ; immediately after the label, so one address serves for both.
        lda #>($2000 + ROW_HINT * 32 + COL_HINT)
        ldx #<($2000 + ROW_HINT * 32 + COL_HINT)
        jsr ppu_set_addr
        ldy #0
@hint:
        lda txt_select,y
        sta PPUDATA
        iny
        cpy #TXT_SELECT_LEN
        bne @hint
        jsr pal_name_point
        ldy #0
@name:
        lda (ptr),y
        sta PPUDATA
        iny
        cpy #SCHEME_NAME
        bne @name
        rts

; ---------------------------------------------------------------------------
;  The range, on the screen that is already there.  Written down the columns
;  rather than along the rows, because down the columns is the order the
;  generator makes it in -- and the PPU will step by 32 instead of 1 if it is
;  asked to.  Rendering is off, so it can be asked directly.
;  in: A = address hi, X = address lo, Y = how many columns
; ---------------------------------------------------------------------------
draw_mountain_cols:
        sta tmp+8
        stx tmp+9
        sty tmp+10
        lda #$04                    ; step down a column, not along a row
        sta PPUCTRL
@col:
        jsr gen_mountain_column
        lda tmp+8
        ldx tmp+9
        jsr ppu_set_addr
        ldy #0
@row:
        lda col_buf,y
        sta PPUDATA
        iny
        cpy #MTN_ROWS
        bne @row
        inc tmp+9                   ; the next column along
        dec tmp+10
        bne @col
        lda #0
        sta PPUCTRL
        rts

; ---------------------------------------------------------------------------
;  Eight attribute bytes to a band, all four quarters of each the same
; ---------------------------------------------------------------------------
draw_attr_bands:
        jsr ppu_set_addr
        ldy #0
@band:
        lda attr_bands,y
        ldx #8
@eight:
        sta PPUDATA
        dex
        bne @eight
        iny
        cpy #8
        bne @band
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
        lda #SOLID_FILL
        bne @put
@some:
        clc
        adc #GRIT_A
@put:
        sta PPUDATA
        dex
        bne @loop
        rts

; ---------------------------------------------------------------------------
;  A run of solid colour 2: rows 26..29, the four under the grit, which are
;  the sand.  It never has to scroll -- one flat colour looks the same
;  wherever it has got to -- and in CLASSIC, where the sand is the sky, it is
;  not there at all.
;  in: A = address hi, X = address lo, Y = how many tiles
; ---------------------------------------------------------------------------
draw_solid_run:
        jsr ppu_set_addr
        lda #SOLID_FILL
@loop:
        sta PPUDATA
        dey
        bne @loop
        rts

; in: A = address hi, X = address lo
ppu_set_addr:
        bit PPUSTATUS
        sta PPUADDR
        stx PPUADDR
        rts
