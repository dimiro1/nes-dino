; ---------------------------------------------------------------------------
;  nes.inc -- the console's registers, by name
; ---------------------------------------------------------------------------

PPUCTRL    = $2000
PPUMASK    = $2001
PPUSTATUS  = $2002
OAMADDR    = $2003
OAMDATA    = $2004
PPUSCROLL  = $2005
PPUADDR    = $2006
PPUDATA    = $2007
OAMDMA     = $4014

SQ1_VOL    = $4000
SQ1_SWEEP  = $4001
SQ1_LO     = $4002
SQ1_HI     = $4003
SQ2_VOL    = $4004
SQ2_SWEEP  = $4005
SQ2_LO     = $4006
SQ2_HI     = $4007
NOISE_VOL  = $400C
NOISE_LO   = $400E
NOISE_HI   = $400F
APUSTATUS  = $4015
APUFRAME   = $4017

JOY1       = $4016
JOY2       = $4017

; PPUSTATUS bits
VBLANK_BIT  = $80
SPRITE0_BIT = $40

; Controller bits, in the order $4016 hands them over
PAD_A      = $80
PAD_B      = $40
PAD_SELECT = $20
PAD_START  = $10
PAD_UP     = $08
PAD_DOWN   = $04
PAD_LEFT   = $02
PAD_RIGHT  = $01
