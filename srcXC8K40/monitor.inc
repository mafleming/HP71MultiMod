
;*******************************************************************************
; MONITOR TASK
; Synopsis
;  When the Idle task detects a character in the serial receive buffer, it
;  transfers control to this task. The Monitor task will disable interrupts
;  while it processes commands from the serial port. Once command processing
;  is complete, interrupts are re-enabled and control returns to the Idle task.
;  Communication with this software is best performed when the HP-71B is turned
;  off to avoid putting the software in an indeterminate state.
; 
; Communication Settings: 19200 baud, 1 stop, no parity, XON/XOFF flow control
; 
; Note: String data statements are limited like DB statements to even lengths
;  because an odd number of characters will have the last byte stored as a null.
; 
; Commands:
; ?
; E[RASE] block#
; I[MAGE] block#
; R[OM] slot# 16K/32K/64K/CHIP block#
; L[AST] slot#
; H[ARD] Y/y/N/n (return toggles)
; C[OMMIT] Y/y/N/n (default no)
; P[LUG] Y/y/N/n
; Q[UIT]
; 
; Commands are not case sensitive. Commands and their arguments are auto
; complete. For example, when specifying ROM size typing 3 results in 32K and a
; space to the block number entry. Invalid keystrokes are ignored.
;*******************************************************************************

        global MONITOR, QCMD, PCMD, HCMD, LCMD, RCMD, CCMD, ECMD, ICMD, XCMD
MONITOR:
        banksel CPUDOZE
        movlw   0x27                ; Clear Doze, Recover on Interrupt, 1:256
        banksel INTCON
;        bcf     INTCON,GIEH         ; High Priority Interrupt Disable
        bcf     GIEH                ; High Priority Interrupt Disable
;        bcf     INTCON,GIEL         ; Low Priority Interrupt Disable
        bcf     GIEL                ; Low Priority Interrupt Disable
        WAIT4RX
        movff    RC1REG,WREG        ; Read character (and discard)
        STROUT  STR01,OUTSTR

        ; Check for and process a command
CMDLOOP:
        banksel RC1STA
        btfss   RC1STA,RC1STA_OERR_POSN,b       ; Overrun error?
        bra     RDLOOP              ; No, go to read loop
        bcf     RC1STA,RC1STA_SPEN_POSN,b       ; Disable serial port to clear error
        bsf     RC1STA,RC1STA_SPEN_POSN,b       ; Reenable serial port
RDLOOP:
;        WAIT4RX
        banksel CMD
        btfsc   SIGPORT,Din,c       ; Exit Monitor if daisy-in asserted
        bra     QEXIT
        banksel PIR3
        btfss   RC1IF               ; Receive Interrupt bit set?
        bra     RDLOOP
        movff   RC1REG,WREG         ; Clear interrupt bit

        banksel CMD
        movwf   CMDBUF,c            ; Save command
        ; Quit command?
        movlw   'Q'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     QCMD
        movlw   'q'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     QCMD
        ; Plug command?
        movlw   'P'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     PCMD
        movlw   'p'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     PCMD
        ; Help command?
        movlw   '?'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     HCMD
        ; Hard command?
        movlw   'H'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     HARDCMD
        movlw   'h'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     HARDCMD
        ; Last command?
        movlw   'L'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     LCMD
        movlw   'l'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     LCMD
        ; ROM command?
        movlw   'R'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     RCMD
        movlw   'r'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     RCMD
        ; COMMIT command?
        movlw   'C'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     CCMD
        movlw   'c'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     CCMD
        ; Erase command?
        movlw   'E'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     ECMD
        movlw   'e'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     ECMD
        ; IMAGE command?
        movlw   'I'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     ICMD
        movlw   'i'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     ICMD
        ; EXECUTE command?
        movlw   'X'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     XCMD
        movlw   'x'
        cpfseq  CMDBUF,c
        bra     $+4
        bra     XCMD
        ; Carriage Return?
        movlw   0x0d
        cpfseq  CMDBUF,c
        bra     CMDLOOP
        call    CHAROUT
        ;
        bra     CMDLOOP
        


;*******************************************************************************
; PROCESS QUIT COMMAND
; Restore the value of TBLPTRU, enable interrupts, and return to power-saving
; mode in the Idle task.
; 
; CMDBUF contains
; (0) 'Q'
;*******************************************************************************
QCMD:
        banksel CMD
        STROUT  STR09,OUTSTR
        ; Restore TBLPTRU before exiting Monitor
        ;btfsc   ROMBANK,2           ; Bank >= 4?
        ;bsf     TBLPTRU,0,0
;        bsf     INTCON,GIEH,0       ; High Priority Interrupt Enable
QEXIT:  bsf     GIEH                ; High Priority Interrupt Enable
;        bsf     INTCON,GIEL,0       ; Low Priority Interrupt Enable
        bsf     GIEL       ; Low Priority Interrupt Enable
        goto    IDLE

;*******************************************************************************
; PROCESS PLUG COMMAND
; Plug or unplug ROMs. A Y means plug just the basics "1" not "3"
; mode in the Idle task.
; 
; CMDBUF contains
; (0) 'P'
;*******************************************************************************
PCMD:
        ; Read back Yy Nn or CR
        STROUT  STR90,OUTSTR
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit
        movwf   CMDBUF+1,c          ; Save response
        ;movf    CMDBUF+1,W          ; Load character to WREG
        rcall   CONFIRM
        bnc     PCMD                ; Not a valid response
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        btfss   WREG,0,c            ; Skip if answer is no
        bra     PUNPLUG             ; Unplug and confirm
        movlw   1                   ; Plug in just main ROMs
        movwf   ROMNUM,c
        STROUT  STR91,OUTSTR        ; Confirmation of ROMs plugged in
        bra     CMDLOOP
PUNPLUG:
        clrf    ROMNUM,c            ; Unplug all ROMs
        STROUT  STR92,OUTSTR        ; Confirmation of ROMs unplugged
        bra     CMDLOOP

;*******************************************************************************
; PROCESS HELP COMMAND
; Output a set of strings to list possible monitor commands.
; 
; CMDBUF contains
; (0) 'H'
;*******************************************************************************
HCMD:
        banksel CMD
        STROUT  STR02,OUTSTR
        STROUT  STR02b,OUTSTR
        STROUT  STR03,OUTSTR
        STROUT  STR04,OUTSTR
        STROUT  STR05,OUTSTR
        STROUT  STR06,OUTSTR
        STROUT  STR07,OUTSTR
        STROUT  STR08,OUTSTR
        bra     CMDLOOP

;*******************************************************************************
; PROCESS ROM COMMAND
; Transfer control to address 02000h
; This is a hidden command to transfer control to PIC18 code stored in the
; "hidden" ROM as uploaded with the IMAGE command.
; The uploaded code can be used as an alternative to the bootloader.
;*******************************************************************************
XCMD:
        banksel CMD
        STROUT  STR80,OUTSTR
XQUERY:
        ; Read back Yy Nn or CR
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit
        movwf   CMDBUF+1,c          ; Save response
        movf    CMDBUF+1,W,c        ; Load character to WREG
        rcall   CONFIRM
        bnc     XQUERY              ; Not a valid response
        btfsc   WREG,0,c            ; Skip if answer is no
        goto    0x02000             ; Jump to boot code
        STROUT  STR32,OUTSTR        ; Confirmation of cancellation
        bra     CMDLOOP

;*******************************************************************************
; PROCESS HARD COMMAND
; Turn on or off a hard configured ROM in slots 6 & 7, blocks 6 & 7.
; 
; CMDBUF contains
; (0) 'H'
;*******************************************************************************
HARDCMD:
        banksel CMD
        STROUT  STR70,OUTSTR        ; Prompt
HREAD:
        ; Read back Yy Nn or CR
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit
        movwf   CMDBUF+1,c          ; Save response
        movlw   0x0d                ; CR means commit
        cpfseq  CMDBUF+1,c
        bra     HCMD2
HRDYES:
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        STROUT  STR71,OUTSTR        ; Hard ROM enabled
        lfsr    0,ROMDAT            ; Table
        movlw   ROMLEN              ; Length of ROM configuration string
        mullw   HRDSLOT             ; First hard rom slot
        movff   PRODL,WREG          ; index of first hard slot
        addwf   FSR0L,c             ; Start of hard slot
        movlw   teFLAG              ; Offset to flag byte
        bsf     PLUSW0,teHARD,0     ; Set hard flag
        movlw   ROMLEN
        addwf   FSR0L,c             ; Bump to second hard ROM slot
        movlw   teFLAG              ; Offset to flag byte
        bsf     PLUSW0,teHARD,0     ; Set hard flag
        bra     CMDLOOP

HCMD2:
        movf    CMDBUF+1,W,c        ; Load character
        rcall   CONFIRM
        bnc     HARDCMD             ; Not a valid character
        btfsc   WREG,0,c            ; Skip if N|n chosen
        bra     HRDYES
HRDNO:
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        STROUT  STR72,OUTSTR        ; No hard ROM
        lfsr    0,ROMDAT            ; Table
        movlw   ROMLEN              ; Length of ROM configuration string
        mullw   HRDSLOT             ; First hard rom slot
        movff   PRODL,WREG          ; index of first hard slot
        addwf   FSR0L,c             ; Start of hard slot
        movlw   teFLAG              ; Offset to flag byte
        bcf     PLUSW0,teHARD,0     ; Clear hard flag
        movlw   ROMLEN
        addwf   FSR0L,c             ; Bump to second hard ROM slot
        movlw   teFLAG              ; Offset to flag byte
        bcf     PLUSW0,teHARD,0     ; Clear hard flag
        bra     CMDLOOP

;*******************************************************************************
; PROCESS LAST COMMAND
; Designate which is the last slot to be enumerated.
; 
; CMDBUF contains
; (0) 'H'   (1) 1 to 7
;*******************************************************************************
LCMD:
        banksel CMD
        STROUT  STR60,OUTSTR
        ; Read block number
        call    GETSLOT             ; Get slot number
        movwf   CMDBUF+1,c          ; Save binary value
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        movlw   0x0d
        WAIT4TX
        movff   WREG,TX1REG         ; Output CR

        movlw   0x01
        movwf   CNTR,c              ; Slot counter
        lfsr    0,ROMDAT            ; Table
LLOOP:
        movlw   teFLAG              ; Flag byte in table entry
        bcf     PLUSW0,teLAST,0     ; Clear last entry flag
        movf    CNTR,w,c            ; Get slot counter
        cpfseq  CMDBUF+1,c          ; Skip if slot counter = last slot number
        bra     LLNEXT
        movlw   teFLAG              ; Flag byte in table entry
        bsf     PLUSW0,teLAST,0     ; Set last entry flag
LLNEXT:
        incf    CNTR,c              ; Bump slot counter
        movlw   ROMLEN              ; Length of ROM table entry
        addwf   FSR0L,1,0           ; Point to next entry
        movlw   NROMS               ; Loop finished?
        cpfseq  CNTR,c              ; Skip if not done yet
        bra     LLOOP
        bra     CMDLOOP

;*******************************************************************************
; PROCESS ERASE COMMAND
; Erase all sectors in a given block (0 to 7).
; 
; CMDBUF contains
; (0) 'E'   (1) 0 to 7
;*******************************************************************************
ECMD:
        banksel CMD
        STROUT  STR50,OUTSTR
        ; Read block number
        call    GETBLK              ; Get block number
        movwf   CMDBUF+1,c          ; Save binary value
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        movlw   0x0d
        WAIT4TX
        movff   WREG,TX1REG         ; Output CR

        ; Set up loop
        STROUT  STR51,OUTSTR        ; We've started message
        clrf    TBLPTRL,c
        clrf    TBLPTRU,c
        movlw   0x00                ; Check for special case block 0
        cpfseq  (CMDBUF+1),c          ; Skip if regular block 1-7
        bra     EBLK17              ; Set up for blocks 1-7
#ifdef _PIC18F27Q10_INC_
        movlw   0x20                ; Number of sectors per half block
#endif
#ifdef _PIC18F27K40_INC_
        movlw   0x40                ; Number of sectors per half block
#endif
        movwf   CNTR,c
        movlw   0x20                ; Half block 0 starts at 2000h
        movwf   TBLPTRH,c
        bra     ERLOOP
EBLK17:
#ifdef _PIC18F27Q10_INC_
        movlw   0x40                ; Number of sectors per block
#endif
#ifdef _PIC18F27K40_INC_
        movlw   0x80                ; Number of sectors per block
#endif
        movwf   CNTR,c
        movf    CMDBUF+1,w,c        ; Get binary block number
        swapf   WREG,c              ; ADRH should be 0, 40, 80, C0
        bcf     STATUS,C,0          ; Clear carry bit
        rlcf    WREG,f,c            ; If block # >= 4
        rlcf    WREG,f,c            ;  that bit will be shifted to Carry
        movwf   TBLPTRH,c
        clrf    TBLPTRU,c
        bnc     $+4                 ; Block >= 4?
        bsf     TBLPTRU,0,c         ; Address is 1 xx00
ERLOOP:
        ; Erase sector
        rcall   ERASESEC
        ; Loop interate/exit
        bc      ERERROR             ; Test for erase error
#ifdef _PIC18F27Q10_INC_
        incf    TBLPTRH
#endif
#ifdef _PIC18F27K40_INC_
        movlw   0x80  ;.128
        addwf   TBLPTRL,c           ; Bump pointer by flash erase sector size
        movlw   0x00
        addwfc  TBLPTRH,c           ; Bump pointer by flash erase sector size
#endif
        ;banksel CMD
        decfsz  CNTR,c
        bra     ERLOOP

#ifdef _PIC18F27Q10_INC_
        bcf     NVMCON0,NVMEN       ; Disable NVM operation
#endif

        banksel CMD
        STROUT  STR52,OUTSTR
        bra     CMDLOOP
ERERROR:
        banksel CMD
        STROUT  STR53,OUTSTR
        bra     CMDLOOP

;*******************************************************************************
; PROCESS COMMIT COMMAND
; Write content of ROM descriptors in RAM into flash.
; The write word at a time approach is used, but sector at a time is possible.
; 
; CMDBUF contains
; (0) 'C'
;*******************************************************************************
CCMD:
        banksel CMD
        STROUT  STR30,OUTSTR        ; Prompt
CREAD:
        ; Read back Yy Nn or CR
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit
        movwf   CMDBUF+1,c          ; Save response
        movlw   0x0d                ; CR means commit
        cpfseq  CMDBUF+1,c
        bra     COMWRI              ; Return means NO
        bra     CCMD2
COMWRI:
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        STROUT  STR31,OUTSTR        ; Confirmation

        ; Sector read constant sector
        movlw   high(ROM1)          ; ROM string address on mod 256 boundary
        movwf   TBLPTRH,c
        clrf    TBLPTRL,c
        clrf    TBLPTRU,c
        rcall   READSEC             ; Read holding registers
        ;bc      COMERR              ; Error occurred during read
        ; Erase constant sector
        movlw   high(ROM1)          ; ROM string address on mod 256 boundary
        movwf   TBLPTRH,c
        clrf    TBLPTRL,c
        clrf    TBLPTRU,c
        rcall   ERASESEC            ; Erase flash table sector
        bc      COMERR              ; Error occurred during erase
#ifdef _PIC18F27K40_INC_
        ;bsf     TBLPTRL,7           ; Erase the other half of the sector
        ;rcall   ERASESEC            ; Erase flash table sector
        ;bc      COMERR              ; Error occurred during erase
        rcall    WRITEHOLD           ; Write original sector content
#endif

        ; The reverse of the ROMDAT setup in INITVAR
        ;banksel CMD
        movlw   (NROMS+1)*ROMLEN    ; Length of ROM configuration table
        movwf   CNTR,c
        lfsr    0,ROMDAT            ; Transfer target address
        movlw   high(ROM1)          ; ROM string address on mod 256 boundary
        movwf   TBLPTRH,c
        clrf    TBLPTRL,c
        clrf    TBLPTRU,c

WRIBACK:
        ; Write data to constant sector
        movff   POSTINC0,TABLAT    ; Low byte of PFM word
        tblwt   *+                  ; Write to sector holding registers
        ; Loop update and end check
        decfsz  CNTR,1,0            ; Done when counter is zero
        bra     WRIBACK

        movlw   high(ROM1)          ; ROM string address on mod 256 boundary
        movwf   TBLPTRH,c
        clrf    TBLPTRL,c
        clrf    TBLPTRU,c
        rcall   WRITESEC            ; Write flash table sector
        bc      COMERR2             ; Carry set indicates write error
        ;
        bra     CMDLOOP
        ;
CCMD2:
        movf    CMDBUF+1,W,c        ; Load character
        rcall   CONFIRM
        bnc     CREAD               ; Not a valid character
        btfsc   WREG,0,c            ; Skip if N|n chosen
        bra     COMWRI
COMCNCL:
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        STROUT  STR32,OUTSTR        ; Confirmation
        bra     CMDLOOP

COMERR:
        banksel CMD
        STROUT  STR33,OUTSTR        ; Error erasing sector
        bra     CMDLOOP
COMERR2:
        banksel CMD
        STROUT  STR41,OUTSTR        ; Error writing word
        bra     CMDLOOP


;*******************************************************************************
; PROCESS IMAGE COMMAND
; Read string of hex characters and write to flash memory. Non-hex characters
; ignored. Process is terminated by two or more carriage returns. Reads a line
; at a time, sends ^S to pause sending, writes data to flash and checks for
; validity. Resumes with ^Q.
;
; NOTE: Can't echo characters received! Looks like I'm overrunning the serial
; buffer when uploading a file via TeraTerm. Even with echo disabled I end up
; erroring out on a word write at 9600 baud. Run slower?
; 
; CMDBUF contains
; (0) 'I'   (1) 0 to 7
;*******************************************************************************
ICMD:
        banksel CMD
        STROUT  STR40,OUTSTR        ; Prompt
        ; Read block number
        call    GETBLK              ; Get block number
        movwf   CMDBUF+1,c          ; Save binary value
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        movlw   0x0d
        WAIT4TX
        movff   WREG,TX1REG         ; Output CR

        ; Form NVM Address
        lfsr    0,DATABUF           ; Save a line of data here
        clrf    CNTR,c              ; Keep track of # of bytes in a line
        movlw   0x00                ; Check for special case block 0
        cpfseq  CMDBUF+1,c          ; Skip if block # is 0
        bra     IMG17               ; Process regular block number
        clrf    TBLPTRL,c
        movlw   0x20                ; Half block 0 starts at 2000h
        movwf   TBLPTRH,c
        clrf    TBLPTRU,c
        bra     IMGSTART
IMG17:
        movf    CMDBUF+1,w,c        ; Get binary block number
        swapf   WREG,f,c            ; NVMADRH should be 0, 40, 80, C0
        bcf     STATUS,C,0          ; Clear carry bit
        rlcf    WREG,f,c            ; If block # >= 4
        rlcf    WREG,f,c            ;  that bit will be shifted to Carry
        movwf   TBLPTRH,c
        clrf    TBLPTRU,c
        bnc     $+4                 ; Block >= 4?
        bsf     TBLPTRU,0,c         ; Address is 1 xx00
        clrf    TBLPTRL,c
IMGSTART:

        ; Read first hex digit. CR ends line of data
ILOOP:
        WAIT4RX
        movff   RC1REG,CMDBUF+2     ; Clear interrupt bit
        movlw   0x0d
        cpfseq  CMDBUF+2,c          ; Skip if CR
        bra     ILP11               ; Look for valid hex character
        bra     WRIBUF              ; Write a line of data or exit process
ILP11:   movlw   0x0d
        cpfseq  CMDBUF+2,c          ; Skip if LF (Unix file)
        bra     ICHK1               ; Look for valid hex character
        bra     WRIBUF              ; Write a line of data or exit process
ICHK1:
        movlw   0x1a                ; ^Z also terminates process
        cpfseq  CMDBUF+2,c          ; Skip if terminated
        bra     $+4                 ; Skip the branch to exit
        bra     IDONE               ; Exit process
        movf    CMDBUF+2,w,c        ; Pass character to ASC2HEX
        call    ASC2HEX             ; Get first hex digit
        bc      ILOOP               ; Carry set means not valid digit
        movwf   CMDBUF+3,c
        swapf   CMDBUF+3,f,c        ; First digit is high nibble

        ; Read second hex digit. CR should be an error.
ILOOP2:
        WAIT4RX
        movff   RC1REG,CMDBUF+2     ; Clear interrupt bit
        movlw   0x0d
        cpfseq  CMDBUF+2,c          ; Skip if CR
        bra     ILP21               ; Look for valid hex character
ILP21:   movlw   0x0d
        cpfseq  CMDBUF+2,c          ; Skip if LF (Unix file)
        bra     ICHK2               ; Look for valid hex character
        bra     ILOOP2              ; Should jump to an error routine
ICHK2:
        movf    CMDBUF+2,w,c        ; Pass character to ASC2HEX
        call    ASC2HEX             ; Get first hex digit
        bc      ILOOP2              ; Carry set means not valid digit
        iorwf   CMDBUF+3,c          ; Form complete byte
        ; Code change to prevent buffer overrun
        ;movff   CMDBUF+3,POSTINC0   ; Save byte to buffer
        movff   CMDBUF+3,INDF0      ; Save byte to buffer
        incf    FSR0L,c             ; Increment pointer, wrap around buffer
        ; End buffer overrun code change
        incf    CNTR,c              ; Byte counter
        bra     ILOOP               ; Get next byte

WRIBUF:
        movlw   0x00                ; See if data buffer is empty
        cpfsgt  CNTR,c              ; A zero counter means we're done
        bra     IDONE
        WAIT4TX
        movlw   0x13                ; Send ^S, DC3
        movwf   TX1REG,c            ; flow stop
        lfsr    0,DATABUF           ; Copy data to flash
        rcall   NVMLINE             ; Write Data Buffer to Flash
        bc      IMERR               ; Carry set, write or verify error

INEXT:
        WAIT4TX
        movlw   0x11                ; Send ^Q, DC3
        movwf   TX1REG,c            ; flow start
        lfsr    0,DATABUF           ; Reset to start of buffer
        WAIT4RX
        movff   RC1REG,CMDBUF+2     ; Clear interrupt bit
        movlw   0x0d                ; Check for CR-LF line ending
        cpfseq  CMDBUF+2,c          ; Skip if LF (CR-LF)
        bra     ICHK1               ; Look for valid hex character
        bra     ILOOP               ; Read next character after CR-LF

IMERR:
        ; Toss remaining characters until termination
ITOSS:
        banksel CMD
        STROUT  STR41,OUTSTR
        WAIT4TX
        movlw   0x11                ; Send ^Q, DC3
        movwf   TX1REG,c            ; flow start
        WAIT4RX
        movff   RC1REG,CMDBUF+2     ; Clear interrupt bit
        movlw   0x0d
        cpfseq  CMDBUF+2,c          ; Skip if CR
        clrf    CNTR,c              ; Something besides CR
        incf    CNTR,c
        movlw   0x03                ; Successive CRs terminate
        cpfslt  CNTR,c
        bra     IFAIL               ; Exit process
        bra     ITOSS
WRIODD:
IFAIL:
        banksel CMD
        STROUT  STR41,OUTSTR
        WAIT4TX
        movlw   0x11                ; Send ^Q, DC3
        movwf   TX1REG,c            ; flow start
        STROUT  STR41,OUTSTR
        WAIT4TX
        movlw   0x11                ; Send ^Q, DC3
        movwf   TX1REG,c            ; flow start
#ifdef _PIC18F27Q10_INC_
        banksel NVMADR
        bcf     NVMCON0,NVMEN       ; Disable NVM operation
#endif
        banksel CMD
        bra     CMDLOOP
IDONE:
#ifdef _PIC18F27Q10_INC_
        banksel NVMADR
        bcf     NVMCON0,NVMEN       ; Disable NVM operation
#endif
        banksel CMD
        STROUT  STR52,OUTSTR
        bra     CMDLOOP

;*******************************************************************************
; PROCESS ROM COMMAND
; Compose a ROM table entry from values specified by the user. The table entry
; is stored in RAM and must be written to flash by the COMMIT command in order
; to be made permanent.
; 
; Details
;  There are 7 ROM slots corresponding to the 7 available PFM blocks. The slot
;  numbers are in the range 1 to 7. A slot holds a ROM or Chip ID and the
;  location of ROM content in one of the 7 available PFM blocks.
; 
; CMDBUF contains
; (0) 'R'   (1) 1 to 7   (2) 1|3|6|c|C   (3) ID5   (4) 0-7
;*******************************************************************************
RCMD:
        banksel CMD
        STROUT  STR10,OUTSTR
        ; Get slot (1 to 7)
RSLOT:
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit
        movwf   CMDBUF+1,c          ; Save slot number
        movlw   0x0d                ; CR now means list all slot info
        cpfseq  CMDBUF+1,c
        bra     RSLOT2
        bra     RLIST
RSLOT2:
        movlw   '0'
        cpfsgt  CMDBUF+1,c          ; Skip if value > 0
        bra     RSLOT
        movlw   '8'
        cpfslt  CMDBUF+1,c          ; Skip if value < 8
        bra     RSLOT
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        movlw   ' '
        WAIT4TX
        movff   WREG,TX1REG         ; Output space
        movlw   '0'                 ; Convert ASCII digit to binary value
        subwf   CMDBUF+1,c
        ; Get size (16K, 32K, 64K)
RSIZE:
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit
        movwf   CMDBUF+2,c          ; Save ROM size
        movlw   0x0d                ; CR now means list slot info
        cpfseq  CMDBUF+2,c
        bra     RSIZ16              ; Continue with check
        bra     RLIST
RSIZ16:
        movlw   '1'                 ; 16K?
        cpfseq  CMDBUF+2,c
        bra     RSIZ32
        STROUT  STR11,OUTSTR
        movlw   0x0a                ; Size nibble value for 16K ROM image
        movwf   CMDBUF+2,c          ; Store value
        movlw   0x08                ; EOM flag
        movwf   CMDBUF+3,c          ; Store value
        bra     RBANK
RSIZ32:
        movlw   '3'                 ; 32K?
        cpfseq  CMDBUF+2,c
        bra     RSIZ64
        STROUT  STR12,OUTSTR
        movlw   0x09                ; Size nibble value for 32K ROM image
        movwf   CMDBUF+2,c          ; Store value
        movlw   0x08                ; EOM flag
        movwf   CMDBUF+3,c          ; Store value
        bra     RBANK
RSIZ64:
        movlw   '6'                 ; 64K?
        cpfseq  CMDBUF+2,c
        bra     RSZCHP1
        STROUT  STR13,OUTSTR
        movlw   0x08                ; Size nibble value for 64K ROM image
        movwf   CMDBUF+2,c          ; Store value
        movlw   0x08                ; EOM flag
        movwf   CMDBUF+3,c          ; Store value
        bra     RBANK
RSZCHP1:
        movlw   'c'                 ; 64K?
        cpfseq  CMDBUF+2,c
        bra     RSZCHP2
        STROUT  STR14,OUTSTR
        movlw   0x0a                ; Size nibble value for 16K ROM image
        movwf   CMDBUF+2,c          ; Store value
        movlw   0x00                ; No EOM, CHIP
        movwf   CMDBUF+3,c          ; Store value
        bra     RBANK
RSZCHP2:
        movlw   'C'                 ; 64K?
        cpfseq  CMDBUF+2,c
        bra     RSIZE               ; Key was invalid, try again
        STROUT  STR14,OUTSTR
        movlw   0x0a                ; Size nibble value for 16K ROM image
        movwf   CMDBUF+2,c          ; Store value
        movlw   0x00                ; No EOM, CHIP
        movwf   CMDBUF+3,c          ; Store value
RBANK:
        call    GETBLK
        movwf   CMDBUF+4,c          ; Save block number
        WAIT4TX
        movff   RC1REG,TX1REG       ; Echo character
        movlw   0x0d
        WAIT4TX
        movff   WREG,TX1REG         ; Output newline
        ; Update ROM slot with new values
RUPDATE:
        movf    CMDBUF+1,w,c        ; Load slot number
        decf    WREG,f,c            ; Slot index starts at zero
        mullw   ROMLEN              ; Length of a ROM slot * slot number
        lfsr    0,ROMDAT            ; Base address of ROM slot 0
        movf    PRODL,w,c           ; Load product
        addwf   FSR0L,f,c           ; Point to base of ROM slot N
        movlw   teID1               ; Offset to ROM size nibble
        movff   CMDBUF+2,PLUSW0     ; Set ROM size
        movlw   teID5               ; ID nibble 5
        movff   CMDBUF+3,PLUSW0     ; Set EOM flag true/false
        movlw   teBANK              ; Offset to ROM bank byte
        movff   CMDBUF+4,PLUSW0     ; Set ROM bank
        rrncf   CMDBUF+4,c          ; Form the address data
        rrncf   CMDBUF+4,c          ; for the mapping table
        rrncf   CMDBUF+4,c
        movlw   0x00                ; Check special case block 0
        cpfsgt  CMDBUF+4,c          ; Skip if normal block number
        bsf     CMDBUF+4,4,c        ; Pattern for hidden block 0
        movlw   teADDR              ; Offset to mapping table data value
        movff   CMDBUF+4,PLUSW0     ; Set mapping table data
        ;
        bra     CMDLOOP



;*******************************************************************************
; OUTPUT ROM SLOT INFO
; List the size and block information for ROM slots.
;*******************************************************************************
RLIST:
        banksel CMD
        STROUT  STR20,OUTSTR        ; Output title
        lfsr    0,ROMDAT            ; Point to first ROM entry
        movlw   NROMS               ; Maximum entries to scan
        movwf   CNTR,c              ; Loop counter
        movlw   '1'                 ; Slot number
        movwf   TEMP,c
RLOOP:
        STROUT  STR10,OUTSTR        ; 'ROM '
        movf    TEMP,w,c            ; Get slot number
        call    CHAROUT
        movlw   ' '
        call    CHAROUT
        incf    TEMP,f,c            ; Bump to next slot number
        movlw   teID1               ; ROM size index
        movff   PLUSW0,ROMSIZ
        movlw   0x0a                ; 16K ROM size
        cpfseq  ROMSIZ,c            ; Skip if size is > 16K
        bra     R32
        STROUT  STR11,OUTSTR        ; '16K '
        bra     RBNK
R32:
        movlw   0x09                ; 32K ROM size
        cpfseq  ROMSIZ,c            ; Skip if size is > 32K
        bra     R64
        STROUT  STR12,OUTSTR        ; '32K '
        bra     RBNK
R64:
        STROUT  STR13,OUTSTR        ; '64K '
RBNK:
        movlw   teBANK              ; ROM block index
        movff   PLUSW0,WREG         ; Get bank number
        addlw   '0'
        call    CHAROUT
        movlw   ' '
        call    CHAROUT
        movlw   teID5               ; EOM ID nibble
        btfss   PLUSW0,teEOM,0      ; Skip if EOM bit set
        call    RCHIP
        movlw   teID5               ; EOM ID nibble
        btfsc   PLUSW0,teEOM,0      ; Skip if EOM bit not set
        call    REOM
        movlw   teFLAG              ; Is this the last enumerated ROM?
        btfss   PLUSW0,teLAST,0     ; skip if not last
        bra     RHARD               ; Check Hard ROM
        STROUT  STR28,OUTSTR        ; 'LAST'
        bra     RLEND               ; Go to end of loop
RHARD:
        btfss   PLUSW0,teHARD,0     ; skip if not hard
        bra     RLEND
        STROUT  STR29,OUTSTR        ; 'HARD'
RLEND:
        movlw   0x0d
        call    CHAROUT
        movlw   ROMLEN              ; Length of ROM table entry
        addwf   FSR0L,1,0           ; Point to next entry
        decfsz  CNTR,c              ; End of table?
        bra     RLOOP
        bra     CMDLOOP

RCHIP:
        STROUT  STR291,OUTSTR       ; 'CHIP '
        return

REOM:
        STROUT  STR292,OUTSTR       ; 'EOM  '
        return



;*******************************************************************************
; OUTPUT STRING
; Output a string to the serial port console. TBLPTR should have the starting
; address of the string. A string is null-terminated.
;*******************************************************************************
OUTSTR:
#ifdef _PIC18F27K40_INC_
;        bcf     NVMCON1,NVMREG0,A   ; point to Program Flash Memory
;        bsf     NVMCON1,NVMREG1,A   ; access Program Flash Memory
        bcf     NVMREG0             ; point to Program Flash Memory
        bsf     NVMREG1             ; access Program Flash Memory
#endif
        tblrd   *+
        movlw   0x00                ; Strings are terminated with null byte
        banksel CMD
        cpfsgt  TABLAT,0            ; Skip if not null terminator
        return
        WAIT4TX
        movff   TABLAT,TX1REG       ; Output character to serial port
        bra     OUTSTR


;*******************************************************************************
; OUTPUT A CHARACTER
; Output a character in WREG to the serial port
;*******************************************************************************
CHAROUT:
        WAIT4TX
        movff   WREG,TX1REG         ; Output block number
        return


;*******************************************************************************
; GET A SLOT NUMBER
; Read a digit from 1 to 7 from the serial port, Return the binary value in
; WREG and the ASCII character in variable location ADIGIT.
;*******************************************************************************
GETSLOT:
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit

        movwf   ADIGIT,c            ; Save copy of ASCII digit
        ; If Escape character, go back to command loop
        movlw   0x1b                ; ESCAPE
        cpfseq  ADIGIT,c
        bra     SLOTCHK
        bra     CANCLOUT            ; Cancel operation
SLOTCHK:
        movlw   '0'
        cpfsgt  ADIGIT,c            ; Skip if value > 0
        bra     GETSLOT
        movlw   '8'
        cpfslt  ADIGIT,c            ; Skip if value < 8
        bra     GETSLOT
        movlw   '0'                 ; Convert ASCII number
        subwf   ADIGIT,w,c          ; and return binary value in WREG
        return


;*******************************************************************************
; GET A BLOCK NUMBER
; Read a digit from 0 to 7 from the serial port, Return the binary value in
; WREG and the ASCII character in variable location ADIGIT.
;*******************************************************************************
GETBLK:
        WAIT4RX
        movff   RC1REG,WREG         ; Clear interrupt bit

        movwf   ADIGIT,c            ; Save copy of ASCII digit
        ; If Escape character, go back to command loop
        movlw   0x1b                ; ESCAPE
        cpfseq  ADIGIT,c
        bra     BLKCHK
CANCLOUT:
        STROUT  STR32,OUTSTR        ; 'Cancelled'
        movlw   high(CMDLOOP)       ; Replace top of stack return address
        movwf   TOSH,c              ; with command loop
        movlw   low(CMDLOOP)
        movwf   TOSL,c
        return
BLKCHK:
        movlw   '0'-1
        cpfsgt  ADIGIT,c            ; Skip if value >= 0
        bra     GETBLK
        movlw   '8'
        cpfslt  ADIGIT,c            ; Skip if value < 8
        bra     GETBLK
        movlw   '0'                 ; Convert ASCII number
        subwf   ADIGIT,w,c          ; and return binary value in WREG
        return


;*******************************************************************************
; ASCII TO HEX
; Read a character from the serial port, If a hex digit, return the binary value
; in WREG and the ASCII character in variable location ADIGIT. Set carry bit if
; not a hex digit
;*******************************************************************************
ASC2HEX:
        movwf   ADIGIT,c            ; Save character
        banksel CMD
        movlw   '0'-1
        cpfsgt  ADIGIT,c            ; Skip if value >= 0
        bra     NOTHEX
        movlw   '9'+1
        cpfslt  ADIGIT,c            ; Skip if value =< 9
        bra     CHKA2F              ; See if the character is A-F, a-f
        movlw   '0'                 ; Convert ASCII number
        subwf   ADIGIT,w,c          ; and return binary value in WREG
        bcf     CARRY               ; Flag as a hex digit
        return
CHKA2F:
        movlw   'A'-1
        cpfsgt  ADIGIT,c            ; Skip if value >= A
        bra     NOTHEX
        movlw   'F'+1
        cpfslt  ADIGIT,c            ; Skip if value =< F
        bra     CHKA2F2             ; See if the character is a-f
        movlw   'A'-0xa             ; Convert ASCII A-F to 10 to 15
        subwf   ADIGIT,w,c          ; and return binary value in WREG
        bcf     CARRY               ; Flag as a hex digit
        return
CHKA2F2:
        movlw   'a'-1
        cpfsgt  ADIGIT,c            ; Skip if value >= A
        bra     NOTHEX
        movlw   'f'+1
        cpfslt  ADIGIT,c            ; Skip if value =< F
        bra     NOTHEX              ; See if the character is a-f
        movlw   'a'-0xa             ; Convert ASCII a-f to 10 - 15
        subwf   ADIGIT,w,c          ; and return binary value in WREG
        bcf     CARRY               ; Flag as a hex digit
        return
NOTHEX:
        bsf     CARRY               ; Flag as not hex digit
        return


;*******************************************************************************
; CONFIRM Y OR N
; Checks to see if a character is Y|y or N|n
; Character passed in WREG
; Carry set if a match is found. WREG set to 0 (N) or 1 (Y)
;*******************************************************************************
CONFIRM:
        movwf   TEMP,c              ; Save character
        movlw   'Y'                 ; Affirm
        cpfseq  CMDBUF+1,c
        bra     CONF1
        bra     CONFY
CONF1:
        movlw   'y'                 ; Affirm
        cpfseq  TEMP,c
        bra     CONF2
        bra     CONFY              ; Commit to flash
CONF2:
        movlw   'N'                 ; Decline
        cpfseq  TEMP,c
        bra     CONF3
        bra     CONFN
CONF3:
        movlw   'n'                 ; Decline
        cpfseq  TEMP,c
        bra     CONFX
CONFN:
        movlw   0x00                ; Decline
        bsf     CARRY               ; Valid entry
        return
CONFY:
        movlw   0x01                ; Affirm
        bsf     CARRY               ; Valid entry
        return
CONFX:
        movlw   0x00                ; Decline
        bcf     CARRY               ; Invalid entry
        return


;*******************************************************************************
; WRITE NVM LINE
; Write a buffer of characters to NVM. Maximum of 255 characters.
; FSR0 points to the data buffer, CNTR is the length of the line buffer, and
; TBLPTR points to the NVM starting address for the write. Buffer should begin
; at a page boundary.
; Return carry clear for OK, carry set for NVM write or verify error.
;*******************************************************************************
NVMLINE:
#ifdef _PIC18F27Q10_INC_
        movff   TBLPTRU,NVMADRU     ; Copy TBLPTR to NVMADR for Q10
        movff   TBLPTRH,NVMADRH
        movff   TBLPTRL,NVMADRL

NVMLOOP:
        ;banksel CMD
        movlw   0x00                ; End of data?
        cpfsgt  CNTR                ; Skip if more data to write
        bra     NVMLDONE            ; Get next line of data
        movff   POSTINC0,NVMDATL    ; Get two bytes to write a word
        decf    CNTR
        clrf    WREG,0
        cpfsgt  CNTR                ; Skip if more data to write
        bra     NVMLERR             ; Odd # of bytes, issue error message
        movff   POSTINC0,NVMDATH    ; Second byte in high byte of word
        decf    CNTR
        call    NVMWORD
        ; Loop update and end check
        btfsc   NVMCON0,NVMERR      ; Skip if no error
        bra     NVMLERR

NVMLCONT:
        ; Verify data was written
        tblrd   *+
        movff   TABLAT,WREG         ; Get low byte
        cpfseq  NVMDATL             ; Check for equality
        bra     NVMLERR
        tblrd   *+
        movff   TABLAT,WREG         ; Get high byte
        cpfseq  NVMDATH             ; Check for equality
        bra     NVMLERR
        ; Increment NVM pointer and loop
        incf    NVMADRL             ; Limited to 128 instruction words
        incf    NVMADRL             ; Limited to 128 instruction words
        ; Check for carry and increment NVMADRH
        bc      $+4
        bra     NVMLOOP
        incf    NVMADRH
        ; Check for carry and increment NVMADRH
        bc      $+4
        bra     NVMLOOP
        incf    NVMADRU
        bra     NVMLOOP
#endif
        ;
#ifdef _PIC18F27K40_INC_
NVMLOOP:
        ;banksel CMD
        movff   POSTINC0,TABLAT     ; Get byte
        tblwt   *+
        decfsz  CNTR,c              ; Skip if data remains
        bra     NVMLOOP

        tblrd   *-                  ; Point back to within sector to write
       bcf     NVMREG0               ; point to Program Flash Memory
       bsf     NVMREG1               ; access Program Flash Memory
       bsf     WREN                  ; enable write to memory
       bcf     FREE                  ; enable write to memory
       bcf     GIEH                  ; disable interrupts
       bcf     GIEL                  ; disable interrupts
        movlw   0x55
        movwf   NVMCON2,c
        movlw   0xAA
        movwf   NVMCON2,c
       bsf     WR                    ; Start erase (CPU stalls)
       bsf     GIEL                  ; re-enable interrupts
       bsf     GIEH                  ; re-enable interrupts
       bcf     WREN                  ; disable writes to memory
       btfsc   WRERR                 ; Check write error flag, skip if OK
       bsf     CARRY                 ; Error
        tblrd   *+                  ; Point back to next byte location
#endif

NVMLDONE:
        bcf     CARRY               ; Signal success
        return

NVMLERR:
        bsf     CARRY               ; Signal failure
        return


;*******************************************************************************
; WRITE NVM WORD
; Write the word in the NVMDATL/NVMDATH registers to flash at the address in
; NVMADR.
; My earlier problems seem to have been caused by interrupts intefering with
; the program process.
;*******************************************************************************
NVMWORD:
#ifdef _PIC18F27Q10_INC_
        banksel INTCON
        bcf     INTCON,GIE          ; Disable interrupts
        ; PFM Unlock Sequence
        banksel NVMADR
        bcf     NVMCON0,NVMERR      ; Clear error bit
        bsf     NVMCON0,NVMEN       ; Enable NVM operation
        movlw   0x55                ; First unlock byte
; ---------------------------------------------------------------------
        movwf   NVMCON2             ; These four steps must be uninterrupted
        movlw   0xaa                ; Second unlock byte
        movwf   NVMCON2
        bsf     NVMCON1,WR          ; Set WR bit to begin write
; ---------------------------------------------------------------------
        banksel INTCON
        bcf     INTCON,GIE          ; Enable interrupts
#endif
        return


;*******************************************************************************
; ERASE NVM SECTOR
; Erase the sector addressed by the TBLPTR register
; Return carry set if a write error occurred, or carry clear if successful
;*******************************************************************************
ERASESEC:
#ifdef _PIC18F27Q10_INC_
        movff   TBLPTRU,NVMADRU     ; Copy TBLPTR to NVMADR for Q10
        movff   TBLPTRH,NVMADRH
        clrf    NVMADRL             ; Make sure it's a sector boundary
        bcf     STATUS,C            ; Carry clear means no error occurred
        ;banksel NVMADR
        bcf     NVMCON0,NVMERR      ; Clear error flag
        bsf     NVMCON0,NVMEN       ; Enable NVM operation
        movlw   0xcc                ; First unlock byte
; ---------------------------------------------------------------------
        movwf   NVMCON2             ; These four steps must be uninterrupted
        movlw   0x33                ; Second unlock byte
        movwf   NVMCON2
        bsf     NVMCON1,SECER       ; Starts erase (10 ms)
; ---------------------------------------------------------------------
        btfsc   NVMCON0,NVMERR      ; Skip if no error
        bsf     STATUS,C            ; Carry set means an error occurred
#endif

#ifdef _PIC18F27K40_INC_
        bcf     CARRY               ; Carry clear means no error occurred
       bcf     NVMREG0               ; point to Program Flash Memory
       bsf     NVMREG1               ; access Program Flash Memory
       bsf     WREN                  ; enable write to memory
       bsf     FREE                  ; enable erase memory
       bcf     GIE                   ; disable interrupts
;       bcf     GIEH                  ; disable interrupts
;       bcf     GIEL                  ; disable interrupts
        movlw   0x55
        movwf   NVMCON2,c
        movlw   0xAA
        movwf   NVMCON2,c
       bsf     WR                    ; Start erase (CPU stalls)
;       bsf     GIEL                  ; re-enable interrupts
;       bsf     GIEH                  ; re-enable interrupts
       bsf     GIE                   ; re-enable interrupts
       bcf     WREN                  ; disable writes to memory
       btfsc   WRERR                 ; Skip if error bit clear
       bsf     CARRY
#endif

        return


;*******************************************************************************
; READ NVM SECTOR
; Read an NVM sector into holding registers using the NVMADR register address.
; Use TBLPTR to point to and read/write holding registers.
; Return carry set if an error occurred, or carry clear if successful
;*******************************************************************************
READSEC:
#ifdef _PIC18F27Q10_INC_
        ;banksel NVMADR
        movff   TBLPTRU,NVMADRU     ; Copy TBLPTR to NVMADR for Q10
        movff   TBLPTRH,NVMADRH
        clrf    NVMADRL             ; Make sure it's a sector boundary
        bcf     STATUS,C            ; Carry clear means no error occurred
        bcf     NVMCON0,NVMERR      ; Clear error bit
        bsf     NVMCON0,NVMEN       ; Enable NVM operation
        movlw   0xbb                ; First unlock byte
; ---------------------------------------------------------------------
        movwf   NVMCON2             ; These four steps must be uninterrupted
        movlw   0x44                ; Second unlock byte
        movwf   NVMCON2
        bsf     NVMCON1,SECRD       ; Starts read
        bcf     NVMCON0,NVMEN       ; Disable NVM operation
        btfsc   NVMCON0,NVMERR      ; Skip if no error
        bsf     STATUS,C            ; Carry set means an error occurred
; ---------------------------------------------------------------------
#endif

#ifdef _PIC18F27K40_INC_
        ; The K40 doesn't have a read holding registers command
	; Read data into buffer
        bcf     NVMREG0             ; point to Program Flash Memory
        bsf     NVMREG1             ; access Program Flash Memory
        lfsr    1,SECTBUF           ; Staging area
        movlw   0x80                ; sector size
        movwf   CNTR,c
RSLOOP:
        tblrd   *+
        movff   TABLAT,POSTINC1     ; Save byte
        decfsz  CNTR,c
        bra     RSLOOP
        bcf     CARRY               ; Carry clear means no error occurred
#endif

        return


;*******************************************************************************
; WRITE HOLDING BUFFER
; Write the data buffer to the sector pointed to by TBLPTR
;*******************************************************************************
WRITEHOLD:
#ifdef _PIC18F27K40_INC_
        ; The K40 doesn't have a read holding registers command
	; Read data into buffer
        bcf     NVMREG0             ; point to Program Flash Memory
        bsf     NVMREG1             ; access Program Flash Memory
        lfsr    1,SECTBUF           ; Staging area
        movlw   0x80                ; sector size
        movwf   CNTR,c
WHLOOP:
        movff   POSTINC1,TABLAT     ; Save byte
        tblwt   *+
        decfsz  CNTR,c
        bra     WHLOOP
        bcf     CARRY               ; Carry clear means no error occurred
#endif

        return


;*******************************************************************************
; WRITE NVM SECTOR
; Write the sector addressed by the NVMADR register from holding registers.
; Return carry set if a write error occurred, or carry clear if successful
;*******************************************************************************
WRITESEC:
#ifdef _PIC18F27Q10_INC_
        ;banksel NVMADR
        movff   TBLPTRU,NVMADRU     ; Copy TBLPTR to NVMADR for Q10
        movff   TBLPTRH,NVMADRH
        clrf    NVMADRL             ; Make sure it's a sector boundary
        bcf     CARRY               ; Carry clear means no error occurred
        bcf     NVMCON0,NVMERR      ; Clear error bit
        bsf     NVMCON0,NVMEN       ; Enable NVM operation
        movlw   0xdd                ; First unlock byte
; ---------------------------------------------------------------------
        movwf   NVMCON2             ; These four steps must be uninterrupted
        movlw   0x22                ; Second unlock byte
        movwf   NVMCON2
        bsf     NVMCON1,SECWR       ; Starts write (10 ms)
        bcf     NVMCON0,NVMEN       ; Disable NVM operation
        btfsc   NVMCON0,NVMERR      ; Skip if no error
        bsf     CARRY               ; Carry set means an error occurred
; ---------------------------------------------------------------------
#endif

#ifdef _PIC18F27K40_INC_
       bcf     NVMREG0               ; point to Program Flash Memory
       bsf     NVMREG1               ; access Program Flash Memory
       bsf     WREN                  ; enable write to memory
       bcf     FREE                  ; enable write to memory
       bcf     GIEH                  ; disable interrupts
       bcf     GIEL                  ; disable interrupts
       movlw   0x55
       movwf   NVMCON2,c
       movlw   0xAA
       movwf   NVMCON2,c
       bsf     WR                    ; Start erase (CPU stalls)
       bsf     GIEL                  ; re-enable interrupts
       bsf     GIEH                  ; re-enable interrupts
       bcf     WREN                  ; disable writes to memory
       btfsc   WRERR                 ; Skip if error bit clear
       bsf     CARRY
#endif

       return


;*******************************************************************************
; STRING DATA
; The XC8 assembler unfortunately doesn't support strings, only a series of
; characters. Strings need to be an even number of characters to fit into a
; 16-bit Program Flash Memory word. Very messy!
;*******************************************************************************
STR01:  db    'T', 'y', 'p', 'e', ' ', '?', ' ', 'f', 'o', 'r'
        db    ' ', 'h', 'e', 'l', 'p', 13, 13, 0
STR02:  db    '?', ' ', 13, 'R', 'O', 'M', ' ', '[', 's', 'l'
        db    'o', 't', ' ', 's', 'i', 'z', 'e', ' ', 'b', 'l'
        db    'o', 'c', 'k', ']', 13,0
STR02b: db    'P', 'L', 'U', 'G', ' ', 'Y', ' ', 'o', 'r', ' '
        db    'N', 13,0
STR03:  db    'E', 'R', 'A', 'S', 'E', ' ', 'b', 'l', 'o', 'c'
        db    'k', ' ', 13,0
STR04:  db    'I', 'M', 'A', 'G', 'E', ' ', 'b', 'l', 'o', 'c'
        db    'k', ' ', 13,0
STR05:  db    'L', 'A', 'S', 'T', ' ', 's', 'l', 'o', 't', ' ', 13,0
STR06:  db    'H', 'A', 'R', 'D', ' ', 'Y', ' ', 'o', 'r', ' '
        db    'N', ' ', 13,0
STR07:  db    'C', 'O', 'M', 'M', 'I', 'T', ' ', 'Y', ' ', 'o'
        db    'r', ' ', 'N', ' ', 13,0
STR08:  db    'Q', 'U', 'I', 'T', 13, 13,0
STR09:  db    'Q', 'U', 'I', 'T', 13, 'B', 'y', 'e', 13, 13, 0
STR10:  db    'R', 'O', 'M', ' ', 0
STR11:  db    '1', '6', 'K', ' ', 0
STR12:  db    '3', '2', 'K', ' ', 0
STR13:  db    '6', '4', 'K', ' ', 0
STR14:  db    'C', 'H', 'I', 'P', ' ', 0
STR20:  db    13, 13, 'R', 'O', 'M', ' ', 'L', 'I', 'S', 'T', 13, 0
STR20b: db    '0', ' ', 0
STR21:  db    '1', ' ', 0
STR22:  db    '2', ' ', 0
STR23:  db    '3', ' ', 0
STR24:  db    '4', ' ', 0
STR25:  db    '5', ' ', 0
STR26:  db    '6', ' ', 0
STR27:  db    '7', ' ', 0
STR28:  db    'L', 'A', 'S', 'T', 0
STR29:  db    'H', 'A', 'R', 'D', 0
STR291: db    'C', 'H', 'I', 'P', ' ', 0
STR292: db    'E', 'O', 'M', ' ', ' ', 0
STR30:  db    'C', 'O', 'M', 'M', 'I', 'T', '?', ' ', '(', 'Y'
        db    '/', 'n', ')', ' ', 0
STR31:  db    13, 'C', 'o', 'n', 'f', 'i', 'r', 'm', 'e', 'd', 13, 13, 0
STR32:  db    13, 'C', 'a', 'n', 'c', 'e', 'l', 'l', 'e', 'd', 13, 13, 0
STR33:  db    13, 'C', 'o', 'u', 'l', 'd', 'n', "'", 't', ' '
        db    'e', 'r', 'a', 's', 'e', ' ', 's', 'e', 'c', 't'
        db    'o', 'r', 13, 13, 0
STR40:  db    'I', 'M', 'A', 'G', 'E', ' ', 0
STR41:  db    'E', 'r', 'r', 'o', 'r', ' ', 'w', 'r', 'i', 't'
        db    'i', 'n', 'g', ' ', 'w', 'o', 'r', 'd', 13, 0
STR50:  db    'E', 'R', 'A', 'S', 'E', ' ', 0
STR51:  db    'E', 'r', 'a', 's', 'i', 'n', 'g', '.', '.', '.', 13, 0
STR52:  db    'D', 'o', 'n', 'e', 13, 0
STR53:  db    'E', 'r', 'r', 'o', 'r', ' ', 'e', 'r', 'a', 's'
        db    'i', 'n', 'g', ' ', 's', 'e', 'c', 't', 'o', 'r', 13, 0
STR60:  db    'L', 'A', 'S', 'T', ' ', 0
STR70:  db    'H', 'A', 'R', 'D', ' ', 0
STR71:  db    13, 'H', 'a', 'r', 'd', ' ', 'R', 'O', 'M', ' '
        db    'p', 'r', 'e', 's', 'e', 'n', 't', 13, 0
STR72:  db    13, 'H', 'a', 'r', 'd', ' ', 'R', 'O', 'M', ' '
        db    'n', 'o', 't', ' ', 'p', 'r', 'e', 's', 'e', 'n', 't', 13, 0
STR80:  db    'X', 'E', 'C', 'U', 'T', 'E', ' ', '-', ' ', 'T'
        db    'r', 'a', 'n', 's', 'f', 'e', 'r', ' ', 'P', 'r'
        db    'o', 'c', 'e', 's', 's', 'o', 'r', ' ', 'C', 'o'
        db    'n', 't', 'r', 'o', 'l', 13
        db    'W', 'A', 'R', 'N', 'I', 'N', 'G', '!', ' ', 'M'
        db    'a', 'k', 'e', ' ', 's', 'u', 'r', 'e', ' ', 'v'
        db    'a', 'l', 'i', 'd', ' ', 'P', 'I', 'C', ' ', 'c'
        db    'o', 'd', 'e', ' ', 'i', 's', ' ', 'i', 'n', ' '
        db    'b', 'l', 'o', 'c', 'k', ' ', '0', '!', '!', 13
        db    '(', 'Y', '/', 'N', ')', ' ',0
STR90:  db    'P', 'L', 'U', 'G', ' ', 'R', 'O', 'M', 's', ' '
        db    'I', 'N', '?', ' ', '(', 'Y', '/', 'N', ')', ' ', 0
STR91:  db    13, 'M', 'a', 'i', 'n', ' ', 'R', 'O', 'M', 's'
        db    ' ', 'p', 'l', 'u', 'g', 'g', 'e', 'd', ' ', 'i', 'n', 13, 0
STR92:  db    13, 'A', 'l', 'l', ' ', 'R', 'O', 'M', 's', ' '
        db    'u', 'n', 'p', 'l', 'u', 'g', 'g', 'e', 'd', 13, 0
