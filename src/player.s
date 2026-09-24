; ===========================================================================
;  player.s -- the dino
; ===========================================================================
;  Jumping is a velocity against a constant gravity, in 8.8 fixed point:
;  -4.6 px/frame against 0.22 px/frame^2 tops out 48 pixels up after 21
;  frames and is back on the ground 21 frames later.  A large cactus is 24
;  pixels, so a jump taken anywhere near the right moment clears one.
;
;  Letting go of the button on the way up trims the climb, and holding Down
;  in the air drops the dino hard -- both of which the browser's does too.
; ===========================================================================

.segment "CODE"

player_init:
        lda #DINO_TOP
        sta dino_y
        lda #0
        sta dino_y_frac
        sta dino_vel_lo
        sta dino_vel_hi
        sta dino_state
        sta dino_anim
        lda #6
        sta dino_timer
        rts

player_update:
        lda dino_state
        cmp #1
        beq @airborne

        lda pad1
        and #(PAD_A | PAD_UP)
        bne @jump

        lda pad1
        and #PAD_DOWN
        bne @duck

        lda #0                      ; running
        sta dino_state
        lda #DINO_TOP
        sta dino_y
        jmp @animate

@jump:
        jsr player_jump
        jmp @animate

@duck:
        lda #2
        sta dino_state
        lda #DUCK_TOP
        sta dino_y
        jmp @animate

@airborne:
        jsr player_physics

@animate:
        lda dino_state
        cmp #1
        beq @done                   ; a jump holds one pose all the way
        dec dino_timer
        bne @done
        lda #8                      ; legs move faster the faster it runs
        sec
        sbc speed_hi
        cmp #3
        bcs @ok
        lda #3
@ok:
        sta dino_timer
        lda dino_anim
        eor #$01
        sta dino_anim
@done:
        rts

player_jump:
        lda #1
        sta dino_state
        lda #JUMP_VEL_LO
        sta dino_vel_lo
        lda #JUMP_VEL_HI
        sta dino_vel_hi
        lda #DINO_TOP
        sta dino_y
        lda #0
        sta dino_y_frac
        lda #SFX_JUMP
        jmp sound_play

player_physics:
        ; Still climbing with the button let go?  Cut the climb short, which
        ; is what turns one button into a short hop and a long one.
        lda dino_vel_hi
        bpl @gravity
        lda pad1
        and #(PAD_A | PAD_UP)
        bne @gravity
        lda dino_y                  ; not yet at the minimum height: let it rise
        cmp #(DINO_TOP - MIN_JUMP_H + 1)
        bcs @gravity
        lda dino_vel_hi
        cmp #VEL_CUT_HI             ; $FB..$FD are faster up than the cut
        bcs @gravity
        lda #VEL_CUT_LO
        sta dino_vel_lo
        lda #VEL_CUT_HI
        sta dino_vel_hi

@gravity:
        lda pad1
        and #PAD_DOWN
        beq @normal
        lda #GRAVITY_FAST
        bne @apply
@normal:
        lda #GRAVITY
@apply:
        clc
        adc dino_vel_lo
        sta dino_vel_lo
        lda dino_vel_hi
        adc #0
        sta dino_vel_hi

        lda dino_y_frac
        clc
        adc dino_vel_lo
        sta dino_y_frac
        lda dino_y
        adc dino_vel_hi
        sta dino_y

        lda dino_vel_hi
        bmi @done                   ; still on the way up
        lda dino_y
        cmp #DINO_TOP
        bcc @done                   ; still above the line
        lda #DINO_TOP               ; landed
        sta dino_y
        lda #0
        sta dino_y_frac
        sta dino_vel_lo
        sta dino_vel_hi
        sta dino_state
        lda #NZ_LAND
        jsr noise_play
@done:
        rts
