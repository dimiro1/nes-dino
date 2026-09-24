; ===========================================================================
;  data.s -- the tables
; ===========================================================================

.segment "RODATA"

; ---------------------------------------------------------------------------
;  Four colours, twice: once for the background and once for the sprites.
;  Colour 3 is deliberately the same as the backdrop -- that is what makes
;  the sprite-0 marker opaque to the PPU and invisible to everyone else.
; ---------------------------------------------------------------------------
palette_day:
        .byte $30, $00, $0F, $30
        .byte $30, $00, $0F, $30
palette_night:
        .byte $0F, $10, $30, $0F
        .byte $0F, $10, $30, $0F

; ---------------------------------------------------------------------------
;  What comes next, drawn from eight slots so the odds can be shaped: a lone
;  small cactus is the commonest thing and a double large one the rarest.
; ---------------------------------------------------------------------------
obst_choice:
        .byte OB_SMALL1, OB_SMALL1, OB_SMALL2, OB_SMALL3
        .byte OB_LARGE1, OB_LARGE1, OB_LARGE2, OB_PTERO

; Indexed by obstacle kind, OB_NONE first
; The bird's entry is the ground it reserves so no cactus is drawn under the
; spot it starts from; its own box lives with the bird, not here.
obst_width_cols:
        .byte 0, 1, 2, 3, 2, 4, 3
obst_width_px:
        .byte 0, 8, 16, 24, 16, 32, 24
obst_hit_l:
        .byte 0, 1, 1, 1, 3, 3, 0
obst_hit_w:
        .byte 0, 6, 14, 22, 10, 26, 0
obst_hit_t:
        .byte 0, CACTUS_S_TOP, CACTUS_S_TOP, CACTUS_S_TOP
        .byte CACTUS_L_TOP, CACTUS_L_TOP, 0

; Two of the four are the middle height, which is the interesting one
ptero_heights:
        .byte PTERO_LOW, PTERO_MID, PTERO_HIGH, PTERO_MID

cloud_start_x:
        .byte 40, 130, 210
cloud_base_y:
        .byte 32, 56, 80

; ---------------------------------------------------------------------------
;  Text, already in tile numbers
; ---------------------------------------------------------------------------
txt_game_over:
        .byte LETTER_G, LETTER_A, LETTER_M, LETTER_E, BG_BLANK
        .byte LETTER_O, LETTER_V, LETTER_E, LETTER_R
txt_press_start:
        .byte LETTER_P, LETTER_R, LETTER_E, LETTER_S, LETTER_S, BG_BLANK
        .byte LETTER_S, LETTER_T, LETTER_A, LETTER_R, LETTER_T
txt_restart_top:
        .byte RESTART + 0, RESTART + 1
txt_restart_bot:
        .byte RESTART + 2, RESTART + 3

; ---------------------------------------------------------------------------
;  Sound.  Sixteen steps an effect: volume, then the period split in two.
;  A volume of $FF is the end of the effect.
; ---------------------------------------------------------------------------
sfx_vol:
        ; jump -- a short rising chirp that fades as it goes
        .byte $0F,$0F,$0E,$0D,$0B,$09,$06,$03
        .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        ; hundred points -- two clean beeps, the second higher
        .byte $0C,$0C,$0C,$00,$00,$0C,$0C,$0C
        .byte $0C,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        ; death -- a long slide down
        .byte $0F,$0F,$0E,$0E,$0D,$0C,$0A,$08
        .byte $06,$04,$02,$01,$FF,$FF,$FF,$FF
        ; setting off -- two notes up
        .byte $0A,$0A,$0A,$0A,$00,$0C,$0C,$0C
        .byte $0C,$0C,$FF,$FF,$FF,$FF,$FF,$FF
sfx_lo:
        .byte $16,$FA,$E1,$CD,$B9,$A5,$91,$7B
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $5C,$5C,$5C,$5C,$5C,$4A,$4A,$4A
        .byte $4A,$00,$00,$00,$00,$00,$00,$00
        .byte $80,$AA,$D7,$04,$40,$90,$F4,$6C
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $9F,$9F,$9F,$9F,$9F,$69,$69,$69
        .byte $69,$69,$00,$00,$00,$00,$00,$00
sfx_hi:
        .byte $01,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$01,$01,$01,$01,$02
        .byte $03,$03,$03,$03,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00

; The noise channel, eight steps each.  A lower period number is a higher
; hiss, so a thump starts low and falls away.
nz_vol:
        ; landing
        .byte $05,$03,$02,$01,$FF,$FF,$FF,$FF
        ; crashing
        .byte $0A,$09,$07,$05,$03,$02,$01,$FF
nz_period:
        .byte $0C,$0D,$0D,$0E,$00,$00,$00,$00
        .byte $08,$09,$0A,$0B,$0C,$0D,$0E,$00
