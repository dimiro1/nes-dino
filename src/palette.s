; ===========================================================================
;  palette.s -- the colour schemes, and the button that walks through them
; ===========================================================================
;  The game opens in CLASSIC, which is the grey on white the browser draws,
;  and stays there until the player presses Select.  That is the whole of the
;  rule: the colours are there, but nobody is given them who did not ask.
;
;  A scheme is nine colours (see scheme_table), and the thirty-two bytes the
;  PPU actually wants are built back up from them every time one is written.
;  Which half of a scheme is in force -- the day one or the night one -- is
;  the same `night` flag the score has always flipped, so a scheme and the
;  time of day are independent of each other.
; ===========================================================================

.segment "CODE"

; ---------------------------------------------------------------------------
;  Select, at any point in the game: the next scheme along, and round again.
;  It is one command in the queue, so this is safe to do in the middle of a
;  run -- nothing stops moving while it happens.
; ---------------------------------------------------------------------------
palette_button:
        lda pad1_new
        and #PAD_SELECT
        beq @done
        ldx pal_scheme
        inx
        cpx #NUM_SCHEMES
        bcc @set
        ldx #0
@set:
        stx pal_scheme
        lda #1
        sta pal_dirty               ; the NMI hands it to the PPU
        lda game_state
        cmp #ST_READY
        bne @done
        jsr queue_scheme_name       ; the title screen says which one it is
@done:
        rts

; ---------------------------------------------------------------------------
;  ptr -> the nine colours in force: the chosen scheme, and inside it the
;  day half or the night one.
; ---------------------------------------------------------------------------
pal_point:
        lda pal_scheme
        asl a
        ora night                   ; which half of which scheme
        sta tmp+7
        asl a
        asl a
        asl a                       ; eight colours to a half...
        clc
        adc tmp+7                   ; ...and one more, so SCHEME_BYTES of them
        clc
        adc #<scheme_table
        sta ptr
        lda #0
        adc #>scheme_table
        sta ptr+1
        rts

; ---------------------------------------------------------------------------
;  ptr -> the name of the chosen scheme, SCHEME_NAME characters of it
; ---------------------------------------------------------------------------
pal_name_point:
        lda pal_scheme
        asl a
        asl a
        asl a
        sec
        sbc pal_scheme              ; eight of them less one, so seven
        clc
        adc #<txt_scheme_names
        sta ptr
        lda #0
        adc #>txt_scheme_names
        sta ptr+1
        rts

; ---------------------------------------------------------------------------
;  All thirty-two palette bytes, queued for the next vblank.  Every set is
;  the same shape -- the sky, two inks, the sky again -- and pal_recipe says
;  which of the scheme's colours the two inks come from.
; ---------------------------------------------------------------------------
queue_palette:
        jsr pal_point
        lda #32
        sta q_count
        ldx #<($3F00)
        lda #>($3F00)
        jsr q_cmd
        lda #0
        sta tmp+7
@set:
        jsr pal_inks                ; tmp+8 and tmp+9, this set's two inks
        ldy #0
        lda (ptr),y
        jsr q_push                  ; colour 0, the sky
        lda tmp+8
        jsr q_push                  ; colour 1
        lda tmp+9
        jsr q_push                  ; colour 2
        ldy #0
        lda (ptr),y
        jsr q_push                  ; colour 3, the sky again
        inc tmp+7
        lda tmp+7
        cmp #8
        bne @set
        rts

; ---------------------------------------------------------------------------
;  The same thirty-two, written straight at the PPU.  Only the first screen
;  does this, with the beam off and the NMI out of the way; every later
;  change goes through the queue above.
; ---------------------------------------------------------------------------
pal_write_all:
        jsr pal_point
        lda #$3F
        ldx #$00
        jsr ppu_set_addr
        lda #0
        sta tmp+7
@set:
        jsr pal_inks
        ldy #0
        lda (ptr),y
        sta PPUDATA                 ; colour 0, the sky
        lda tmp+8
        sta PPUDATA                 ; colour 1
        lda tmp+9
        sta PPUDATA                 ; colour 2
        ldy #0
        lda (ptr),y
        sta PPUDATA                 ; colour 3, the sky again
        inc tmp+7
        lda tmp+7
        cmp #8
        bne @set
        rts

; ---------------------------------------------------------------------------
;  The two inks of palette tmp+7, looked up through the recipe and left in
;  tmp+8 and tmp+9 -- out of the way of q_push, which wants X for itself.
; ---------------------------------------------------------------------------
pal_inks:
        lda tmp+7
        asl a                       ; two recipe bytes to a palette
        tax
        ldy pal_recipe,x
        lda (ptr),y
        sta tmp+8
        ldy pal_recipe+1,x
        lda (ptr),y
        sta tmp+9
        rts

; ---------------------------------------------------------------------------
;  The name on the title screen's second line, rewritten in place.  It sits
;  after SELECT and its two blanks, so only these characters ever change.
; ---------------------------------------------------------------------------
queue_scheme_name:
        jsr pal_name_point
        lda #ROW_HINT
        sta txt_row
        lda #COL_HINT + TXT_SELECT_LEN
        sta txt_col
        lda #SCHEME_NAME
        sta txt_len
        jmp queue_text
