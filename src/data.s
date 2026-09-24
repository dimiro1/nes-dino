; ===========================================================================
;  data.s -- the tables
; ===========================================================================

.segment "RODATA"

; ---------------------------------------------------------------------------
;  The colour schemes
; ---------------------------------------------------------------------------
;  Every tile in the game is drawn in one ink on a transparent backdrop, and
;  only two reach for a second: the ground band and the mountains.  So a whole
;  scheme is nine colours, and the thirty-two bytes the PPU wants are built
;  back up from them.  Each comes twice over, day then night, because the
;  world turns dark every seventh hundred points.
;
;      sky     the backdrop.  Every colour-0 pixel on the screen is this one,
;              whichever palette picked it, which is exactly why the palettes
;              can be handed out by band and never have to follow the scroll
;      ink     the score bar and the messages
;      cactus
;      line    the ground line, and the grit sitting on the sand
;      sand    the band below the line.  Set to the sky in CLASSIC, where it
;              disappears and leaves the browser's bare horizon
;      mtns    the range along the horizon
;      dino
;      bird
;      cloud
; ---------------------------------------------------------------------------
scheme_table:
        ;      sky  ink  cact line sand mtns dino bird clud
        ; CLASSIC -- the game as the browser draws it: a grey dino on a white
        ; page, with the sand set to the sky so the band below the line is
        ; not there at all, and the range left as a faint grey outline
        .byte $30, $00, $00, $00, $30, $10, $00, $00, $00
        .byte $0F, $10, $10, $10, $0F, $00, $10, $10, $10
        ; DESERT -- blue sky, red dino, green cacti, gold sand, and an olive
        ; range along the back of it
        .byte $21, $0F, $1A, $17, $28, $08, $16, $37, $30
        .byte $01, $30, $1A, $18, $08, $0F, $26, $37, $11
        ; SUNSET -- everything a silhouette against the low sun, then embers
        .byte $27, $0F, $0F, $0F, $07, $16, $0F, $0F, $37
        .byte $0F, $37, $17, $27, $07, $04, $37, $16, $04
        ; POCKET -- four shades of green, the way a handheld screen did it
        .byte $29, $0F, $0F, $0F, $09, $19, $0F, $0F, $19
        .byte $09, $29, $29, $29, $0F, $19, $29, $29, $19

; ---------------------------------------------------------------------------
;  Which of those nine colours each palette's two inks are.  The PPU holds
;  four background palettes and four sprite ones; every one of them is the
;  same shape -- the sky, two inks, and the sky again in colour 3, which is
;  what keeps the sprite-0 marker and the pad under it invisible.
; ---------------------------------------------------------------------------
pal_recipe:
        .byte 1, 5                  ; background 0  the lettering, the range
        .byte 2, 5                  ; background 1  the cacti, the range again
        .byte 3, 4                  ; background 2  the ground line, the sand
        .byte 0, 0                  ; background 3  never selected
        .byte 6, 6                  ; sprite 0      the dino, and sprite 0 itself
        .byte 7, 7                  ; sprite 1      the bird
        .byte 8, 8                  ; sprite 2      the clouds
        .byte 0, 0                  ; sprite 3      never selected

; ---------------------------------------------------------------------------
;  Which palette each band of the screen picks, one byte to four nametable
;  rows.  An attribute byte covers a 32x32 pixel square split into quarters,
;  and multiplying by $55 is the same choice in all four of them.
;
;  It can be this coarse -- and it can be written once at the start and never
;  touched again, even though the world scrolls underneath it -- because the
;  sky between two cacti is colour 0, and colour 0 is the backdrop whichever
;  palette picked it.  Nothing the choice has to follow ever moves sideways;
;  it only has to follow the bands the screen is already in.  That is why a
;  new column of world still carries tiles and nothing else.
; ---------------------------------------------------------------------------
attr_bands:
        .byte PAL_UI     * $55      ; rows  0.. 3  the score bar
        .byte PAL_UI     * $55      ; rows  4.. 7
        .byte PAL_UI     * $55      ; rows  8..11
        .byte PAL_UI     * $55      ; rows 12..15  press start, game over
        .byte PAL_UI     * $55      ; rows 16..19  the restart arrow, and the
                                    ;              top of the range
        .byte PAL_CACTUS * $55      ; rows 20..23  the rest of the range, and
                                    ;              where the cacti stand
        .byte PAL_GROUND * $55      ; rows 24..27  the line, the grit, the sand
        .byte PAL_GROUND * $55      ; rows 28..31  sand all the way down

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

; A cloud stays in its band for the whole run and wanders sixteen lines
; inside it.  The bands are far enough apart that two clouds never share a
; scanline, and the lowest of them stops at 134 -- ten lines clear of
; PTERO_HIGH, so a cloud and a bird cannot share one either.
cloud_start_x:
        .byte 24, 120, 216
cloud_base_y:
        .byte 32, 72, 112

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

; The title screen's second line.  The two blanks are part of it, so the name
; that follows can be rewritten on its own as the player walks through them.
txt_select:
        .byte LETTER_S, LETTER_E, LETTER_L, LETTER_E, LETTER_C, LETTER_T
        .byte BG_BLANK, BG_BLANK
TXT_SELECT_LEN = 8

; Padded to SCHEME_NAME so one name can be written straight over another
txt_scheme_names:
        .byte LETTER_C, LETTER_L, LETTER_A, LETTER_S, LETTER_S, LETTER_I, LETTER_C
        .byte LETTER_D, LETTER_E, LETTER_S, LETTER_E, LETTER_R, LETTER_T, BG_BLANK
        .byte LETTER_S, LETTER_U, LETTER_N, LETTER_S, LETTER_E, LETTER_T, BG_BLANK
        .byte LETTER_P, LETTER_O, LETTER_C, LETTER_K, LETTER_E, LETTER_T, BG_BLANK

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
