; ===========================================================================
;  states.s -- waiting, running, dying, and offering another go
; ===========================================================================

.segment "CODE"

game_init:
        lda #$5A                    ; any non-zero seed; the wait stirs it
        sta rng
        lda #$A3
        sta rng+1
        lda #0
        sta pal_scheme              ; CLASSIC, and game_reset leaves it alone:
                                    ; a scheme outlives the run that chose it
        jsr score_clear_hi
        ; fall through

game_reset:
        jsr score_init              ; hundreds and ptero_on are both read by
        jsr ptero_init              ; the generator, so they go first
        jsr world_init
        jsr mtn_init                ; the horizon is drawn with the first
        jsr player_init             ; screen, so it has to be ready first
        jsr clouds_init
        lda #0
        sta night
        sta night_count
        sta pal_dirty
        sta restart_phase
        sta flash_timer
        sta state_timer
        jsr ppu_draw_first_screen
        lda #ST_READY
        sta game_state
        rts

; ---------------------------------------------------------------------------
;  Nothing moves until the player says so, which is also where the random
;  seed comes from: the exact frame they pressed the button.
; ---------------------------------------------------------------------------
state_ready:
        inc rng
        bne @stirred
        inc rng+1
@stirred:
        lda pad1_new
        and #(PAD_A | PAD_UP | PAD_START)
        beq @done
        jsr queue_clear_prompt
        lda #SFX_START
        jsr sound_play
        lda #ST_RUN
        sta game_state
@done:
        rts

state_run:
        jsr world_update
        jsr player_update
        jsr ptero_update
        jsr clouds_update
        jsr score_update

.ifndef DEBUG_GODMODE
        jsr check_obstacles
        bcs @died
        jsr check_ptero
        bcs @died
.endif
        rts
@died:
        lda #ST_DYING
        sta game_state
        lda #3
        sta dino_state
        lda #DINO_TOP               ; the dead pose stands on the ground
        sta dino_y
        lda #36
        sta state_timer
        lda #SFX_DIE
        jsr sound_play
        lda #NZ_CRASH
        jsr noise_play
        jmp score_check_hi

; ---------------------------------------------------------------------------
;  A beat with everything stopped before the message goes up
; ---------------------------------------------------------------------------
state_dying:
        dec state_timer
        bne @done
        lda #ST_OVER
        sta game_state
        jsr queue_game_over
@done:
        rts

state_over:
        lda pad1_new
        and #(PAD_A | PAD_UP | PAD_START)
        beq @done
        lda #0
        sta ppu_mask                ; one dark frame to rebuild the world in
        lda #1
        sta restart_phase
@done:
        rts

; ---------------------------------------------------------------------------
;  Rebuilding the whole screen needs the beam off and the NMI out of the way,
;  since it writes far more than a vblank holds.
; ---------------------------------------------------------------------------
do_restart:
        lda #0
        sta PPUCTRL
        jsr game_reset
        lda ppu_ctrl
        sta PPUCTRL
        lda #PPUMASK_ON
        sta ppu_mask
        rts

; ---------------------------------------------------------------------------
;  Both lines of the title screen: the prompt, and the colour hint under it
; ---------------------------------------------------------------------------
queue_clear_prompt:
        lda #12
        sta txt_row
        lda #10
        sta txt_col
        lda #11
        sta txt_len
        lda #BG_BLANK
        jsr queue_fill

        lda #ROW_HINT
        sta txt_row
        lda #COL_HINT
        sta txt_col
        lda #TXT_SELECT_LEN + SCHEME_NAME
        sta txt_len
        lda #BG_BLANK
        jmp queue_fill

queue_game_over:
        lda #<txt_game_over
        sta ptr
        lda #>txt_game_over
        sta ptr+1
        lda #13
        sta txt_row
        lda #11
        sta txt_col
        lda #9
        sta txt_len
        jsr queue_text

        lda #<txt_restart_top
        sta ptr
        lda #>txt_restart_top
        sta ptr+1
        lda #15                     ; clear of row 17, where the range starts
        sta txt_row
        lda #15
        sta txt_col
        lda #2
        sta txt_len
        jsr queue_text

        lda #<txt_restart_bot
        sta ptr
        lda #>txt_restart_bot
        sta ptr+1
        lda #16
        sta txt_row
        jmp queue_text
