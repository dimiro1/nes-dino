; ===========================================================================
;  sound.s -- three noises, played a step a frame off a table
; ===========================================================================
;  Two players, one on pulse 1 and one on the noise channel, running at the
;  same time so a landing can thump underneath a chirp.  A pulse effect is
;  sixteen steps of volume, period low and period high; a noise effect is
;  eight of volume and period.  Either ends at a volume of $FF.
;
;  $4003 is only rewritten when the period's high bits actually change, since
;  writing it restarts the waveform and that is audible as a click.
; ===========================================================================

SFX_NONE  = 0
SFX_JUMP  = 1
SFX_POINT = 2
SFX_DIE   = 3
SFX_START = 4

NZ_NONE   = 0
NZ_LAND   = 1
NZ_CRASH  = 2

.segment "CODE"

sound_init:
        lda #$0F
        sta APUSTATUS               ; pulses, triangle and noise all on
        lda #$00
        sta SQ1_SWEEP
        sta SQ2_SWEEP
        lda #$30                    ; constant volume, set to zero
        sta SQ1_VOL
        sta SQ2_VOL
        lda #$30
        sta NOISE_VOL
        lda #SFX_NONE
        sta sfx_id
        sta nsfx_id
        lda #0
        sta sfx_step
        sta nsfx_step
        lda #$FF
        sta sfx_last_hi
        rts

; in: A = effect id
sound_play:
        sta sfx_id
        lda #0
        sta sfx_step
        lda #$FF                    ; no high byte matches, so step 0 always
        sta sfx_last_hi             ; writes $4003 and starts the note
        rts

; in: A = noise effect id
noise_play:
        sta nsfx_id
        lda #0
        sta nsfx_step
        rts

sound_update:
        jsr sound_pulse
        ; and on into the noise player, which is independent of it

sound_noise:
        lda nsfx_id
        beq @done
        sec
        sbc #1
        asl a
        asl a
        asl a                       ; eight steps to a noise effect
        clc
        adc nsfx_step
        tax
        lda nz_vol,x
        cmp #$FF
        beq @stop
        ora #$30                    ; length halted, constant volume
        sta NOISE_VOL
        lda nz_period,x
        sta NOISE_LO
        lda nsfx_step
        bne @running
        lda #$08                    ; load the length counter once, at the start
        sta NOISE_HI
@running:
        inc nsfx_step
        lda nsfx_step
        cmp #8
        bcc @done
@stop:
        lda #$30
        sta NOISE_VOL
        lda #NZ_NONE
        sta nsfx_id
@done:
        rts

sound_pulse:
        lda sfx_id
        beq @done

        sec
        sbc #1
        asl a
        asl a
        asl a
        asl a
        clc
        adc sfx_step
        tax

        lda sfx_vol,x
        cmp #$FF
        beq @stop
        ora #$B0                    ; 50% duty, length halted, fixed volume
        sta SQ1_VOL
        lda sfx_lo,x
        sta SQ1_LO
        lda sfx_hi,x
        cmp sfx_last_hi
        beq @no_retrigger
        sta sfx_last_hi
        sta SQ1_HI
@no_retrigger:
        inc sfx_step
        lda sfx_step
        cmp #16
        bcc @done
@stop:
        lda #$30
        sta SQ1_VOL
        lda #SFX_NONE
        sta sfx_id
@done:
        rts
