;
; SPF - Stress ProDOS Filesystem
; Copyright (C) 2013 - 2025 by David Schmidt
; 1110325+david-schmidt@users.noreply.github.com
;
; This program is free software; you can redistribute it and/or modify it 
; under the terms of the GNU General Public License as published by the 
; Free Software Foundation; either version 2 of the License, or (at your 
; option) any later version.
;
; This program is distributed in the hope that it will be useful, but 
; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
; or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License 
; for more details.
;
; You should have received a copy of the GNU General Public License along 
; with this program; if not, write to the Free Software Foundation, Inc., 
; 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
;

InitTime:
	sec
	jsr $FE1F	; CheckForGS
	bcc FoundClockGS
	jsr CheckForNoSlotClock
	bcc FoundClockNoSlot
	jsr CheckForROMX
	bcc FoundClockROMX
	jsr CheckForMegaFlash
	bcc FoundClockMegaFlash
	jsr CheckForSlottedClocks
	rts

FoundClockGS:
;---------------------------------------------------------
; Patch the entry point of GetTime to the IIgs version
;---------------------------------------------------------
	lda #<GetTimeGS
	sta GetTime+1
	lda #>GetTimeGS
	sta GetTime+2
	rts

FoundClockNoSlot:
;---------------------------------------------------------
; Patch the entry point of GetTime to the NoSlotClock version
;---------------------------------------------------------
	lda #<GetTimeNSC
	sta GetTime+1
	lda #>GetTimeNSC
	sta GetTime+2
	rts

FoundClockROMX:
;---------------------------------------------------------
; Patch the entry point of GetTime to the ROMX version
;---------------------------------------------------------
	lda #<GetTimeROMX
	sta GetTime+1
	lda #>GetTimeROMX
	sta GetTime+2
	rts

FoundClockMegaFlash:
;---------------------------------------------------------
; Patch the entry point of GetTime to the MegaFlash version
;---------------------------------------------------------
	lda #<GetTimeMegaFlash
	sta GetTime+1
	lda #>GetTimeMegaFlash
	sta GetTime+2
	rts

GetTime:
	jsr $0000
	rts


GetTimeGS:
;---------------------------------------------------------
; Get the current time on the GS
;---------------------------------------------------------
.P816
	clc
	.byte $FB	; xce
	rep #$30
.A16
.I16
	pha
	pha
	pha
	pha
	ldx #$0D03
	jsl $E10000
	sep #$30
.I8
	ldx #7
GTGSLoop:
	pla
	sta GSTime,X
	dex
	bpl GTGSLoop
	sec
	.byte $FB	; xce
.A8
	lda GSTime+5	; Hours
	sta TimeNow
	lda GSTime+6	; Minutes
	sta TimeNow+1
	lda GSTime+7	; Seconds
	sta TimeNow+2
	lda #$00	; Hundredths (not available on GS)
	sta TimeNow+3
	rts
.P02

GSTime:
	.res 8

;---------------------------------------------------------
; BASIC test program for the GS time-getting algorithm
;---------------------------------------------------------

;10 X = 768:Z = 803
;20 READ Y: IF Y >  - 1 THEN  POKE X,Y:X = X + 1: GOTO 20
;30 DATA 56,32,31,254,144,1,96,251,194,48,72,72,72,72
;40 DATA 162,3,13,34,0,0,225,226,48,162,7,104,157,35,3
;50 DATA 202,16,249,56,251,96,-1
;60 CALL 768
;70 WD =  PEEK (Z): REM Weekday (1=Sun...7=Sat)
;80 MO =  PEEK (Z+2): REM Month (0=Jan...11=Dec)
;90 DA =  PEEK (Z+3): REM Day (0...30)
;100 YR =  PEEK (Z+4): REM Year-1900
;110 HR =  PEEK (Z+5): REM Hour (0...23)
;120 MN =  PEEK (Z+6): REM Minute (0...59)
;130 SC =  PEEK (Z+7): REM Second (0...59)
;140 PRINT "Hour: ";HR;" Minute: ";MN;" Second: ";SC

GetTimeNSC:
	jsr NSCEntry
	lda L0307	; Hours
	sta TimeNow
	lda L0308	; Minutes
	sta TimeNow+1
	lda L0309	; Seconds
	sta TimeNow+2
	lda L030A	; Hundredths
	sta TimeNow+3
	rts

CheckForROMX:
	; Return with carry clear means we found one
	bit $C0E0	; Temporarily disable Zip Chip
	bit $FACA	; Select ROMX Bank 0
	bit $FACA
	bit $FAFE
	lda $DFFE	; Will return $4A if ROMX present
	cmp #$4A	;  or $AA if ROMX in Recovery mode
	bne NoROMX
	lda $DFFF	; Will return $CD if ROMX present
	cmp #$CD	;  or $55 if ROMX in Recovery mode
	bne NoROMX
	; Here we know we have a ROMX
	clc
	jmp DoneROMX
	NoROMX:
	sec
	DoneROMX:
	bit $F851	; Return to Main Bank (MUST DO, EVEN IF ROMX NOT FOUND!)
	rts

GetTimeROMX:
	bit $C0E0	; Temporarily disable Zip Chip
	bit $FACA
	bit $FACA
	bit $FAFE	; activate bank 0
	jsr $D8F0	; read clock through firmware entry point
	bit $F851	; exit bank 0

	lda $2B2	; Hours
	sta TimeNow
	lda $2B1	; Minutes
	sta TimeNow+1
	lda $2B0	; Seconds + $80 ST Oscillator enabled bit
	and #$7f	; Seconds
	sta TimeNow+2
	lda #$00	; Hundredths (not available on ROMX)
	sta TimeNow+3
	rts

;---------------------------------------------------------
; MegaFlash clock support (Apple IIc/IIc+ with MegaFlash)
; https://github.com/ThomasFok/MegaFlash
;
; Design notes: doc/MegaFlash_Clock.md
;
; Detection: Magic sequence ($C0C2,$C0C0,$C0C0,$C0C3,$C0C1) activates
; device. CMD_GETDEVINFO returns signature $88,$74 in paramreg.
;
; GetTime: CMD_GETPRODOS25TIME returns 6 bytes. Time word (bytes 2-3)
; packs [mday:5][hour:5][min:6]; we extract hour=(time>>6)&$1F,
; min=time&$3F. Byte 1 = seconds.
;---------------------------------------------------------
MF_CMDSTATUS	= $C0C0
MF_PARAM	= $C0C1
MF_DATA		= $C0C2
MF_ID		= $C0C3
MF_CMD_GETDEVINFO	= $10
MF_CMD_GETPRODOS25TIME	= $18
MF_SIGNATURE1	= $88
MF_SIGNATURE2	= $74
MF_BUSY		= $80

CheckForMegaFlash:
	; Activate MegaFlash with magic address sequence
	lda MF_DATA
	lda MF_CMDSTATUS
	lda MF_CMDSTATUS
	lda MF_ID
	lda MF_PARAM
	; Short delay for mode switch (~8us)
	jsr MFShortDelay
	; Send GETDEVINFO command
	lda #MF_CMD_GETDEVINFO
	sta MF_CMDSTATUS
	; Wait for busy to clear (with timeout)
	ldx #100
:	bit MF_CMDSTATUS
	bpl :+
	dex
	bne :-
	; Timeout - MegaFlash not present
	sec
	rts
:	; Check for error (bit 6)
	bvs CheckMegaFlashFail
	; Verify signature bytes
	lda MF_PARAM
	cmp #MF_SIGNATURE1
	bne CheckMegaFlashFail
	lda MF_PARAM
	cmp #MF_SIGNATURE2
	bne CheckMegaFlashFail
	; MegaFlash found
	clc
	rts
CheckMegaFlashFail:
	sec
	rts

MFShortDelay:
	jsr :+
:	rts

GetTimeMegaFlash:
	; Activate MegaFlash
	lda MF_DATA
	lda MF_CMDSTATUS
	lda MF_CMDSTATUS
	lda MF_ID
	lda MF_PARAM
	jsr MFShortDelay
	; Request ProDOS 2.5 format time (includes seconds)
	lda #MF_CMD_GETPRODOS25TIME
	sta MF_CMDSTATUS
	; Wait for completion
:	bit MF_CMDSTATUS
	bmi :-
	bvs GetTimeMFDone	; Error - skip update
	; Read 6 bytes: [0]=4ms units, [1]=sec, [2-3]=time word, [4-5]=date
	lda MF_PARAM		; t4ms - discard
	lda MF_PARAM		; seconds
	sta MFTime+1
	lda MF_PARAM		; time lo
	sta MFTime+2
	lda MF_PARAM		; time hi
	sta MFTime+3
	lda MF_PARAM		; date lo - discard
	lda MF_PARAM		; date hi - discard
	; Extract: min = time & $3F, hour = (time >> 6) & $1F
	lda MFTime+2
	and #$3F
	sta TimeNow+1		; Minutes
	lda MFTime+2
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	sta MFTime+0		; temp: hour low 2 bits
	lda MFTime+3
	and #$07			; hour bits from high byte
	asl a
	asl a
	ora MFTime+0
	sta TimeNow		; Hours
	lda MFTime+1
	sta TimeNow+2		; Seconds
	lda #$00
	sta TimeNow+3		; Hundredths (MegaFlash has 4ms, we use 0 for simplicity)
GetTimeMFDone:
	rts

MFTime:	.res 4		; Temp: [0]=hour bits, [1]=sec, [2]=time_lo, [3]=time_hi

CheckForNoSlotClock:
	jsr PrepNoSlotClock	; Prepare the driver
	jsr NSCEntry		; Call it to get the time
	lda L0304		; Signature will be non-zero if NSC exists
	clc
	bne :+
	sec
:	rts

PrepNoSlotClock:
;---------------------------------------------------------
; Look for a NoSlotClock
;---------------------------------------------------------

L3A3A	= $3A3A
LDA9A	= $DA9A
LDD6C	= $DD6C
LDEBE	= $DEBE
LDFE3	= $DFE3
LE3E9	= $E3E9

L0260:	lda #$00
	sta L02DE
	lda #$03
L0267:  ora #$C0
	sta L031F
L026C:  sta L0322
	sta L0331
	sta L033F
	lda #$03
	sta L02DF
	bne L0292
	brk
	brk
	brk
L027F:  brk
L0280:  brk
	brk
	.byte $2F
L0283:  brk
	brk
	.byte $2F
	brk
	brk
	jsr $0000
	.byte $3A
	brk
	brk
	.byte $3A
	brk
	brk
	.byte $8D
L0292:  jsr NSCEntry
	ldx #$07
L0297:  lda L0303,x
	cmp L02E0,x
	bcc L02AE
	cmp L02E8,x
	bcs L02AE
	dex
	bpl L0297
	dec L02DF
	bne L0292
	clc
	rts
L02AE:  inc L02DE
	lda L02DE
	cmp #$08
	bcc L0267
	bne L02D7
	lda #$C0
	ldy #$15
	sta L031B
	sty L031A
	ldy #$07
	sta L031F
	sty L031E
	dey
	sta L036F
	sty L036E
	lda #$C8
	bne L026C
L02D7:  lda #$4C
	sta L0316
	sec
	rts
L02DE:  brk
L02DF:  brk
L02E0:  brk
	.byte $01, $01, $01
	brk
	brk
	brk
	brk
L02E8:  .byte $64, $0d, $20, $38, $98,$3c, $3c, $64
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	brk
	clc
	.byte $90
L0302:	.byte $09
L0303:  brk
L0304:	brk
	brk
	brk
L0307:	brk
L0308:	brk
L0309:	brk
L030A:	brk
NSCEntry:
	sec
L030C:	php
	sei
	lda #$00
	sta L0304
;	sta L0280
L0316:	lda L03A3
	.byte $AD
L031A:	.byte $FF
L031B:	.byte $CF
	pha
	.byte $8D
L031E:	brk
L031F:  .byte $C3
	.byte $AD
	.byte $04
L0322:	.byte $C3
	ldx #$08
L0325:	lda L03BF,x
	sec
	ror a
L032A:	pha
	lda #$00
	rol a
	tay
	.byte $B9
	brk
L0331:	.byte $C3
	pla
	lsr a
	bne L032A
	dex
	bne L0325
	ldx #$08
L033B:	ldy #$08
L033D:	.byte $AD
	.byte $04
L033F:	.byte $C3
	ror a
	ror $42
	dey
	bne L033D
	lda $42
	sta L027F,x
	lsr a
	lsr a
	lsr a
	lsr a
	tay
	lda $42
	cpy #$00
	beq L035E
	and #$0F
	clc
L0359:	adc #$0A
	dey
	bne L0359
L035E:	sta L0302,x
	dex
	bne L033B
	pla
	bmi L0370
	.byte $8D
L036E:	.byte $FF
L036F:	.byte $CF
L0370:	ldy #$11
	ldx #$06
L03A3:	plp
	bcs L03BF
	jsr LDEBE
	jsr LDFE3
	jsr LDD6C
	sta $85
	sty $86
	lda #$80
	ldy #$02
	ldx #$8D
	jsr LE3E9
	jsr LDA9A
L03BF:	rts
	.byte $5C
	.byte $A3
	.byte $3A
	cmp $5C
	.byte $A3
	.byte $3A
L03C7:	cmp $2F
	.byte $2F
	jsr L3A3A
	.byte $8D, $00, $00

CheckForSlottedClocks:
;---------------------------------------------------------
; Look for clocks via signature in firmware
;---------------------------------------------------------
	sec
FindClockSlot:
	lda #$00
	tay
	sta UTILPTR
	sta ClockSlot
	ldx #$07 ; Slot number
FindClockSlotLoop:
	clc
	txa
	adc #$c0
	sta UTILPTR+1
	ldy #$00		; Lookup offset
	lda (UTILPTR),y
	cmp #$08		; Is $Cn00 == $08?
	bne NotThunder
	iny			; Lookup offset
	lda (UTILPTR),y
	cmp #$78		; Is $Cn01 == $78?
	bne NotThunder
	iny			; Lookup offset
	lda (UTILPTR),y
	cmp #$28		; Is $Cn02 == $28?
	bne NotThunder
; Ok, we have a set of signature bytes for a Thunderclock.
	stx ClockSlot
	jsr PrepThunderclock
	jmp FindClockSlotDone
NotThunder:
	; Check for other slotted clocks
FindClockSlotNext:
	dex
	bne FindClockSlotLoop
; All done now, return with carry clear if we found a clock
FindClockSlotDone:
	sec
	lda ClockSlot
	beq :+
	clc
:	rts
ClockSlot:	.byte 0

PrepThunderclock:
;---------------------------------------------------------
; Patch the entry point of GetTime to the Thunderclock version
;---------------------------------------------------------
	lda #<GetTimeThunderclock
	sta GetTime+1
	lda #>GetTimeThunderclock
	sta GetTime+2
	rts

	rts


GetTimeThunderclock:
;---------------------------------------------------------
; Get the current time from a Thunderclock - and convert from BCD
;---------------------------------------------------------
	lda ClockSlot
	asl a
	asl a
	asl a
	asl a
	tay
	lda #$18
	jsr L701B
	lda #$08
	jsr L701B
	ldx #$0A
L7011:	jsr L7033
	sta L7069,x
	dex
	bne L7011
	clc		; Convert from BCD and copy out time
	lda TKH1	; Multiply 10s of hours by 10, add to units
	ldx #$0a
:	adc TKH2
	dex
	bne :-
	lda TKH2	; Hours
	sta TimeNow
	clc
	lda TKM1	; Multiply 10s of minutes by 10, add to units
	ldx #$0a
:	adc TKM2
	dex
	bne :-
	lda TKM2	; Minutes
	sta TimeNow+1	
	clc
	lda TKS1	; Multiply 10s of seconds by 10, add to units
	ldx #$0a
:	adc TKS2
	dex
	bne :-
	lda TKS2	; Seconds
	sta TimeNow+2
	lda #$00	; Hundredths (not available on Thunderclock)
	sta TimeNow+3
	rts
L701B:	sta $C080,y
	ora #$04
	sta $C080,y
	jsr L702B
	eor #$04
	sta $C080,y
L702B:	jsr L702E
L702E:	pha
	pha
	pla
	pla
	rts
L7033:	pha
	lda #$04
	sta L7068
	lda #$00
	sta L7069
L703E:	lda $C080,y
	asl a
	ror L7069
	pla
	pha
	and #$01
	sta $C080,y
	ora #$02
	sta $C080,y
	eor #$02
	sta $C080,y
	pla
	ror a
	pha
	dec L7068
	bne L703E
	pla
	lda L7069
	clc
	ror a
	ror a
	ror a
	ror a
	rts
L7068:	brk
L7069:	brk
	brk
	brk
	brk
	brk
TKH1:	brk
TKH2:	brk
TKM1:	brk
TKM2:	brk
TKS1:	brk
TKS2:	brk
