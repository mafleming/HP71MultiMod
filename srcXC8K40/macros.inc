;*******************************************************************************
;                                                                              *
;    Filename:      macros.inc                                                 *
;    Date:          July 27, 2020                                              *
;    File Version:  1.0                                                        *
;    Author:        Mark A. Fleming                                            *
;    Company:                                                                  *
;    Description:   Macros used to encapsulate hardware interaction.           *
;                                                                              *
;*******************************************************************************
;    Notes:                                                                    *
;  7/28/2020, Add ,0 to all SFR accesses so that the Access Bank mode is       *
;    used rather and the Bank Select Register.                                 *
;                                                                              *
;*******************************************************************************
;                                                                              *
;    Revision History:                                                         *
;    1.0  27-July-2020                                                         *
;*******************************************************************************
CMDTRIS EQU     TRISB
CMDLAT  EQU     LATB
CMDPORT EQU     PORTB

SIGTRIS EQU     TRISA
SIGLAT  EQU     LATA
SIGPORT EQU     PORTA

; PDIP breakout board
DBGTRIS EQU     TRISC
DBGPORT EQU     PORTC
DBGPIN  EQU     5

; MultiMod board
;DBGTRIS EQU     TRISA
;DBGPORT EQU     PORTA
;DBGPIN  EQU     6

Halt71  EQU     0
IRQ14   EQU     1
Din     EQU     2
CDn     EQU     4
STRn    EQU     3

;*******************************************************************************
; Debugging macros
;*******************************************************************************
#define DBGFLAG                     ; Comment out in production
FLAGHI  MACRO
#ifdef   DBGFLAG
        bsf     DBGPORT,DBGPIN,c
#endif
        endm

FLAGLO  MACRO
#ifdef   DBGFLAG
        bcf     DBGPORT,DBGPIN,c
#endif
        endm

;*******************************************************************************
; Regular macros
;*******************************************************************************

;*******************************************************************************
; Enable bus output drivers for ID, PC READ and DP READ commands
; Consumes 2 Instruction Cycles
DATAOUT MACRO
        ;movlw   0xf0
        ;andwf   CMDTRIS,1,0         ; Clear lower 4 bits
        clrf    CMDTRIS,c
        endm

;*******************************************************************************
; Disable bus output drivers to release the bus
; Consumes 2 Instruction Cycles
DATAIN  MACRO
        movlw   0x0f
        iorwf   CMDTRIS,f,c         ; Set lower 4 bits
        endm

;*******************************************************************************
; Spin-Wait until signal is high
; Consumes 2~4 Instruction Cycles (after signal rise)
POSEDGE MACRO   SIGNAL
        btfss   SIGPORT,SIGNAL,c    ; Skip if SIGNAL has gone high
        bra     $-2
        endm

;*******************************************************************************
; Spin-Wait until signal is low
; Consumes 2~4 Instruction Cycles (after signal fall)
NEGEDGE MACRO   SIGNAL
        btfsc   SIGPORT,SIGNAL,c    ; Skip if SIGNAL has gone low
        bra     $-2
        endm

;*******************************************************************************
; Spin-Wait until signal is low, then enable bus output
; Saves one instruction cycle when not part of a loop, i.e. ID command
; Consumes 4~7 Instruction Cycles
FASTOUT MACRO                       ; Output data as fast as possible
        movlw   0xf0
        btfsc   SIGPORT,STRn,c      ; Skip if STRn is low
        bra     $-2
        andwf   CMDTRIS,f,c         ; Set output enable
        endm

;*******************************************************************************
; Write a literal value to the command bus output latches
; Consumes 2 Instruction Cycles
BUSWRL  MACRO   VALUE               ; Write literal to bus
        movlw   VALUE
        movwf   CMDLAT,c
        endm

;*******************************************************************************
; Write a register value to the command bus output latches
; Consumes 2 Instruction Cycles
BUSWR   MACRO   MEMLOC              ; Write content of location to bus
        movff   MEMLOC,CMDLAT
        endm

;*******************************************************************************
; Read the command bus input values to the W Register
; If upper 4 bits disabled by making them analog, only a read is needed
; Consumes 2 Instruction Cycles
BUSRD   MACRO                       ; Read bus data to WREG
        ; Since upper bits are driven low, masking not needed
        movlw   0x0f                ; Mask off upper nibble
        andwf   CMDPORT,w,c         ; Read command bus
        endm

;*******************************************************************************
; Read a five nibble sequence that forms a CONFIGURE, LOAD PC or LOAD DP
; command. Store the sequence in REGNAME and create a 3 byte TBLPTR value
; placed in PTRNAME.
; This TBLPTR formation is for 16KB ROMs
; A 16KB ROM will fit in any 16KB block.
; TBLPTRU = 0 for blocks 1,2,3   TBLPTRU = 1 for blocks 4,5,6,7
; TBLPTRL = PC/DP register bits 8:1
; TBLPTRH[5:0] = PC/DP register bits 14:9
; TBLPTRH[7:6] = Bank number & 0x3
; 
; There is a potential timing problem when reading the last address nibble at
; the end of this macro. Early 71B models had a long delay of up to 7
; Instruction Cycles (437.5 ns) before data was presented on the bus. So the
; bus should be sampled close to or after the rising edge of the STRn clock.
; The last nibble is being read 2 IC after the falling edge of STRn, but the
; falling edge is sampled late due to there being too many ICs in the previous
; clock half-cycle. An error in reading the last nibble could occur if the
; previous half-cycle is optimized.
; 
LOADREG MACRO   REGNAME,PTRNAME,RNGNAME
        NEGEDGE STRn                ; 2~4 instruction cycles
        ;FLAGHI
        banksel CMD
        POSEDGE STRn                ; 2~4 + 3 instruction cycles
        BUSRD                       ; Nibble 0
        movwf   REGNAME,c
        NEGEDGE STRn                ; 2~4 + 1 instruction cycles
        setf    MIOVLD,c            ; Assume a valid I/O address
        POSEDGE STRn                ; 2~4 + 7 instruction cycles
        BUSRD                       ; Nibble 1
        swapf   WREG,w,c
        iorwf   REGNAME,f,c         ; Put result back into REGNAME
;        bcf     STATUS,C,0          ; Clear carry bit
         bcf     CARRY               ; Clear carry bit.
        rrcf    REGNAME,w,c         ; Construct byte pointer from nibble pointer
        movwf   PTRNAME,c
        NEGEDGE STRn                ; 2~4 + 3 instruction cycles
        ; The MIOADR could be altered by a PC read between LOADDP & READDP
        ;movlw   0x0f                ; MMIO addresses 16 registers
        ;andwf   REGNAME,0           ; Create MMIO register address
        ;movf    MIOADR              ; Save to address register
        POSEDGE STRn                ; 2~4 + 6 instruction cycles
        BUSRD                       ; Nibble 2
        movwf   REGNAME+1,c
        clrf    PTRNAME+2,c         ; Prepare TBLPTRU early
        NEGEDGE STRn                ; 2~4 + 3 instruction cycles
        movf    REGNAME+1,w,c       ; Load nibble 2
        cpfseq  MMIO+2,b            ; Skip if nibble 2 = MMIO nibble 2
        clrf    MIOVLD,c            ; No match, not MMIO address
        ;FLAGLO
        POSEDGE STRn                ; 2~4 + 11 instruction cycles (!)
        BUSRD                       ; Nibble 3
        cpfseq  MMIO+3,b            ; Skip if nibble 3 = MMIO nibble 3
        clrf    MIOVLD,c            ; No match, not MMIO address
        swapf   WREG,w,c
        iorwf   REGNAME+1,f,c       ; Put result back into REGNAME+1
        bcf     CARRY               ; Clear carry bit
        rrcf    REGNAME+1,w,c       ; Form TBLPTRH in WREG
        bnc     $+4                     ; Low bit high? Skip if clear
        bsf     PTRNAME,7,c         ; Previous $+4 was $+2, no skip!
        movwf   PTRNAME+1,c
        bcf     PTRNAME+1,6,c       ; Clear DPREG bit 15
        ; Never merge a NEGEDGE! STRn can get stretched
        NEGEDGE STRn                ; 2~4 + 18 instruction cycles
        nop                         ; Needed for old Saturn processors
        nop
        nop
        nop
        clrf    PTRNAME+2,c
        BUSRD                       ; Nibble 4 (potential timing problem)
        movwf   REGNAME+2,c
        cpfseq  MMIO+4,b            ; Skip if nibble 4 = MMIO nibble 4
        clrf    MIOVLD,c            ; No match, not MMIO address
        rlcf    REGNAME+1,w,c       ; Register bit 15 to carry
        rlcf    REGNAME+2,w,c       ; Register bits 19..15 in WREG
        movff   PLUSW2,RNGNAME      ; Look up address mapping bits
        ;bcf     STATUS,C,0          ; Clear carry bit (not needed)
        rlcf    RNGNAME,w,c         ; Rotate pattern into WREG
        iorwf   PTRNAME+1,f,c         ; (added f)Or pattern bits into Register 15..14
        ;bnc     $+4                 ; No upper pattern bit
        btfsc   RNGNAME,7,c         ; High bit of mapping pattern
        bsf     PTRNAME+2,0,c       ; Address in blocks 4..7
        ;POSEDGE    STRn            ; Merge half-cycles
        endm

;*******************************************************************************
; Increment a 5 nibble register value stored in 3 bytes (legacy)
; Consumes 3~5 Instruction Cycles
INCREG  MACRO   REGNAME             ; Increment 5 nibble register (3 bytes)
        incf    REGNAME,f,c
        bnc     $+8
        incf    REGNAME+1,f,c
        bnc     $+4
        incf    REGNAME+2,f,c
        endm

;*******************************************************************************
; Load TBLPTR from 3 byte memory location.
; Consumes 6 Instruction Cycles
PTRLOAD MACRO   REGNAME
        movff   REGNAME,TBLPTRL
        movff   REGNAME+1,TBLPTRH
        movff   REGNAME+2,TBLPTRU
        endm

;*******************************************************************************
; Save TBLPTR to a 3 byte memory location.
; Consumes 6 Instruction Cycles
PTRSAVE MACRO   REGNAME
        movff   TBLPTRL,REGNAME
        movff   TBLPTRH,REGNAME+1
        movff   TBLPTRU,REGNAME+2
        endm

;*******************************************************************************
; Load TBLPTR with String location, Call subroutine.
STROUT  MACRO   STRINGLOC,PRROUTINE
        movlw   LOW(STRINGLOC)
        movwf   TBLPTRL,c
        movlw   HIGH(STRINGLOC)
        movwf   TBLPTRH,c
        clrf    TBLPTRU,c           ; Address in block 0
        call    PRROUTINE
        endm

;*******************************************************************************
; Wait for receipt of a character on USART1
WAIT4RX MACRO
        banksel PIR3
        btfss   RC1IF               ; Receive Interrupt bit set?
        bra     $-2
        banksel CMD
        endm

;*******************************************************************************
; Wait for ready to send a charater on USART1
WAIT4TX MACRO
        banksel PIR3
        btfss   TX1IF               ; Skip if Transmit Buffer is empty
        bra     $-2
        banksel CMD
        endm
