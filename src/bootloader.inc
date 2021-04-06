; Copyright (c) 2002-2011,  Microchip Technology Inc.
;
; Microchip licenses this software to you solely for use with Microchip
; products.  The software is owned by Microchip and its licensors, and
; is protected under applicable copyright laws.  All rights reserved.
;
; SOFTWARE IS PROVIDED "AS IS."  MICROCHIP EXPRESSLY DISCLAIMS ANY
; WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT
; NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS
; FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.  IN NO EVENT SHALL
; MICROCHIP BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR
; CONSEQUENTIAL DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR
; EQUIPMENT, COST OF PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY
; OR SERVICES, ANY CLAIMS BY THIRD PARTIES (INCLUDING BUT NOT LIMITED
; TO ANY DEFENSE THEREOF), ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION,
; OR OTHER SIMILAR COSTS.
;
; To the fullest extent allowed by law, Microchip and its licensors
; liability shall not exceed the amount of fees, if any, that you
; have paid directly to Microchip to use this software.
;
; MICROCHIP PROVIDES THIS SOFTWARE CONDITIONALLY UPON YOUR ACCEPTANCE
; OF THESE TERMS.
;
; *****************************************************************************

#include "devices.inc"
#include "bootconfig.inc"
;#include "preprocess.inc"
#include "config.inc"

; *****************************************************************************

; *****************************************************************************
#define STX             0x0F            
#define ETX             0x04
#define DLE             0x05
#define NTX             0xFF
; *****************************************************************************

; *****************************************************************************
; RAM Address Map
CRCL                equ 0x00
CRCH                equ 0x01
RXDATA              equ 0x02
TXDATA              equ 0x03

; Framed Packet Format
; <STX>[<COMMAND><ADDRL><ADDRH><ADDRU><0x00><DATALEN><...DATA...>]<CRCL><CRCH><ETX>
COMMAND             equ 0x05        ; receive buffer
ADDRESS_L           equ 0x06
ADDRESS_H           equ 0x07
ADDRESS_U           equ 0x08
ADDRESS_X           equ 0x09
DATA_COUNTL         equ 0x0A
PACKET_DATA         equ 0x0B
DATA_COUNTH         equ 0x0B        ; only for certain commands
; *****************************************************************************

; *****************************************************************************
    errorlevel -311                 ; don't warn on HIGH() operator values >16-bits

#ifdef USE_SOFTBOOTWP
  #ifndef SOFTWP
    #define SOFTWP
  #endif
#endif

#ifdef USE_SOFTCONFIGWP
  #ifdef CONFIG_AS_FLASH
    #ifndef SOFTWP
      #define SOFTWP
    #endif
  #endif
#endif

; *****************************************************************************

 
; *****************************************************************************
; BOOTLOADER_ADDRESS == 0 ****************************************************************
    ORG     0
BootloaderStart:
    ;DigitalInput                ; set RX pin as digital input on certain parts
        bsf     TRISC,7              ; EUSART1 RC7 is RX, disable output
        ;banksel ANSELC
        bcf     ANSELC,7             ; EUSART1 RC7 is RX, enable digital input
    movlw   low(AppVector)      ; load address of application reset vector
    bra     BootloaderBreakCheck

	ORG	    0x0008
HighPriorityInterruptVector:
	goto    AppHighIntVector    ; Re-map Interrupt vector

	ORG	    0x0018
LowPriorityInterruptVector:
	goto    AppLowIntVector     ; Re-map Interrupt vector

BootloaderBreakCheck:

        ; Taken from hp71rom/rommain.asm
        ; Matches AN1310boot	
        movlw   0x60                ; Configure oscillator
        banksel OSCCON1
        movwf   OSCCON1,1
        movlw   0x00
        movwf   OSCCON3,1
        movlw   0x00
        movwf   OSCEN,1
        movlw   0x08
        movwf   OSCFRQ,1
        movlw   0x1F                ; Maximum frequency
        movwf   OSCTUNE,1           ; Recommended by Diego Diaz


        ; Configure serial port
        banksel PMD4
        bcf     PMD4,UART1MD        ; Enable EUSART1
        banksel TRISC
        bcf     TRISC,6              ; EUSART1 RC6 is TX, enable output
        ;movlw   0xbf                ; EUSART1 RC6 is TX
        ;movwf   TRISC,1
        bsf     TRISC,7              ; EUSART1 RC7 is RX, disable output
        bcf     ANSELC,7             ; EUSART1 RC7 is RX, enable digital input
        bsf     WPUC,7               ; Add weak pullup if serial not connected
        ;movlw   0x7f                ; EUSART1 RC7 is RX
        ;movwf   ANSELC,1
        banksel RX1PPS
        movlw   0x17                ; RC7->EUSART1:RX1
        movwf   RX1PPS,1
        movlw   0x09                ; RC6->EUSART1:TX1
        movwf   RC6PPS,1
; From eusart1.c
        banksel BAUD1CON
        movlw   0x0a                ; 16-bit baus rate generator, wake-up
        movwf   BAUD1CON,1          ; enabled, autobaud disabled
        movlw   0x90                ; Serial enabled, 8-bit, continuous receive
        movwf   RC1STA,1
        movlw   0x24                ; Tranmit enabled, 8-bit async, high rate
        movwf   TX1STA,1
; Baud = Fosc/(4*(N+1)) where N = SP1BRGH SP1BRGL
        movlw   0x40                ; 19200 baud (N=832)
        ;movlw   0x82                ; 9600 baud
        ;movlw   0x0a                ; 2400 baud
        movwf   SP1BRGL,1
        movlw   0x03                ; 19200 baud (N=832)
        ;movlw   0x06                ; 9600 baud
        ;movlw   0x1a                ; 2400 baud
        movwf   SP1BRGH,1

    ; This isn't supposed to be needed!!
    ; This may be needed everytime it exits EEPROM or Config write
    bcf     NVMCON1,NVMREG0       ; point to Program Flash Memory
    bsf     NVMCON1,NVMREG1       ; access Program Flash Memory



    bsf     UxRCSTA, CREN       ; start receiving
    btfss   RXPORT, RXPIN
    bra     BootloadMode

CheckAppVector:
    ; Read instruction at the application reset vector location. 
    ; If we read 0xFFFF, assume that the application firmware has
    ; not been programmed yet, so don't try going into application mode.
    movwf   TBLPTRL
    movlw   high(AppVector)
    movwf   TBLPTRH
    bra     CheckAppVector2


CheckAppVector2:
    movlw   upper(AppVector)
    movwf   TBLPTRU     
    tblrd   *+                  ; read instruction from program memory
    incfsz  TABLAT, W           ; if the lower byte != 0xFF, 
GotoAppVector:
    goto    AppVector           ; run application.

    tblrd   *+                  ; read instruction from program memory
    incfsz  TABLAT, W           ; if the lower byte == 0xFF but upper byte != 0xFF,
    bra     GotoAppVector       ; run application.
    ; otherwise, assume application firmware is not present because we read a NOP (0xFFFF).
    ; fall through to bootloader mode...
BootloadMode:
    lfsr    FSR2, 0             ; for compatibility with Extended Instructions mode.
DoAutoBaud:
WaitForHostCommand:
    rcall   ReadHostByte        ; get start of transmission <STX>
    xorlw   STX
    bnz     WaitForHostCommand  ; got something unexpected, keep waiting for <STX>
        
; *****************************************************************************

; *****************************************************************************
; Read and parse packet data.
StartOfLine:
    movlw   STX                     ; send back start of response
    rcall   SendHostByte

    lfsr    FSR0, COMMAND-1         ; Point to the buffer
        
    clrf    ADDRESS_U               ; Clear data left by previous command

ReceiveDataLoop:
    rcall   ReadHostByte            ; Get the data
    xorlw   STX                     ; Check for an unexpected STX
    bz      StartOfLine             ; unexpected STX: abort packet and start over.

NoSTX:
    movf    RXDATA, W
    xorlw   ETX                     ; Check for a ETX
    bz      VerifyPacketCRC         ; Yes, verify CRC

NoETX:
    movf    RXDATA, W
    xorlw   DLE                     ; Check for a DLE
    bnz     AppendDataBuffer

    rcall   ReadHostByte            ; DLE received, get the next byte and store it
    
AppendDataBuffer:
    movff   RXDATA, PREINC0         ; store the data to the buffer
    bra     ReceiveDataLoop

VerifyPacketCRC:
    lfsr    FSR1, COMMAND
    clrf    CRCL
    clrf    CRCH
    movff   POSTDEC0, PRODH         ; Save host packet's CRCH to PRODH for later comparison
                                    ; CRCL is now available as INDF0
VerifyPacketCrcLoop:
    movf    POSTINC1, w
    rcall   AddCrc                  ; add new data to the CRC

    movf    FSR1H, w
    cpfseq  FSR0H
    bra     VerifyPacketCrcLoop     ; we aren't at the end of the received data yet, loop
    movf    FSR1L, w
    cpfseq  FSR0L
    bra     VerifyPacketCrcLoop     ; we aren't at the end of the received data yet, loop

    movf    CRCH, w
    cpfseq  PRODH
    bra     DoAutoBaud              ; invalid CRC, reset baud rate generator to re-sync with host
    movf    CRCL, w
    cpfseq  INDF0
    bra     DoAutoBaud              ; invalid CRC, reset baud rate generator to re-sync with host

; ***********************************************
; Pre-setup, common to all commands.
    clrf    CRCL
    clrf    CRCH

    movf    ADDRESS_L, W            ; Set all possible pointers
    movwf   TBLPTRL
#ifdef __18F27K40
    movwf   NVMADRL
#endif
    movf    ADDRESS_H, W
    movwf   TBLPTRH
#ifdef __18F27K40
    movwf   NVMADRH
#endif
    movff   ADDRESS_U, TBLPTRU
    lfsr    FSR0, PACKET_DATA
; ***********************************************

; *****************************************************************************
; Modified Jan. 31, 2021. MAF
; Need to set NVMREG bits in NVMCON1 to point to PFM or UserID/Config addr.
; This isn't working at the moment. The Client tries to read the Device ID and
; just gets zeros back.
#ifdef __18F27K40
    ;movlw   0x00                  ; Boot LoaderInfo command
    ;cpfsgt  COMMAND
    ;bra     ADDRULE
    movlw   0x1f                  ; TBLPTRU max value for PFM
    cpfsgt  ADDRESS_U,A           ; ADDRU
    bra     ADDRULE
    bsf     NVMCON1,NVMREG0,A     ; point to Config/ID/EEPROM
    bsf     NVMCON1,NVMREG1,A     ; access Config/ID/EEPROM
    bra     ADDRUSKP
ADDRULE
    bcf     NVMCON1,NVMREG0,A     ; point to Program Flash Memory
    bsf     NVMCON1,NVMREG1,A     ; access Program Flash Memory
ADDRUSKP
#endif
 

; ***********************************************
; Test the command field and sub-command.
CheckCommand:
    movlw   .10
    cpfslt  COMMAND
    bra     DoAutoBaud          ; invalid command - reset baud generator to re-sync with host

    ; The following two #if expressions generate the error "Operand contains unresolvable labels or is too complex"
    ; This jump table must exist entirely within one 256 byte block of program memory.
;#if ($ & 0xFF) > (0xFF - .24)
    ; Too close to the end of a 256 byte boundary, push address forward to get code
    ; into the next 256 byte block.
;    messg   "Wasting some code space to ensure jump table is aligned."
;    ORG     $+(0x100 - ($ & 0xFF))
;#endif
    ORG     110
JUMPTABLE_BEGIN:
    movf    PCL, w              ; 0 do a read of PCL to set PCLATU:PCLATH to current program counter.
    rlncf   COMMAND, W          ; 2 multiply COMMAND by 2 (each BRA instruction takes 2 bytes on PIC18)
    addwf   PCL, F              ; 4 Jump in command jump table based on COMMAND from host
    bra     BootloaderInfo      ; 6 00h
    bra     ReadFlash           ; 8 01h
    bra     VerifyFlash         ; 10 02h
    bra     EraseFlash          ; 12 03h
    bra     WriteFlash          ; 14 04h
    bra     ReadEeprom          ; 16 05h
    bra     WriteEeprom         ; 18 06h
    bra     WriteConfig         ; 20 07h
    bra     GotoAppVector       ; 22 08h
    reset                       ; 24 09h
;#if (JUMPTABLE_BEGIN & 0xFF) > ($ & 0xFF)
;    error "Jump table is not aligned to fit within a single 256 byte address range."
;#endif
; *****************************************************************************

WaitForRise:
    clrwdt

WaitForRiseLoop
    btfsc   INTCON, TMR0IF  ; if TMR0 overflowed, we did not get a good baud capture
    return                  ; abort

    btfsc   RXPORT, RXPIN   ; Wait for a falling edge
    bra     WaitForRiseLoop

WtSR:
    btfss   RXPORT, RXPIN   ; Wait for rising edge
    bra     WtSR
    return
; *****************************************************************************

; 16-bit CCITT CRC
; Adds WREG byte to the CRC checksum CRCH:CRCL. WREG destroyed on return.
AddCrc:                           ; Init: CRCH = HHHH hhhh, CRCL = LLLL llll
    xorwf   CRCH, w               ; Pre:  HHHH hhhh     WREG =      IIII iiii
    movff   CRCL, CRCH            ; Pre:  LLLL llll     CRCH =      LLLL llll
    movwf   CRCL                  ; Pre:  IIII iiii     CRCL =      IIII iiii
    swapf   WREG                  ; Pre:  IIII iiii     WREG =      iiii IIII
    andlw   0x0F                  ; Pre:  iiii IIII     WREG =      0000 IIII
    xorwf   CRCL, f               ; Pre:  IIII iiii     CRCL =      IIII jjjj
    swapf   CRCL, w               ; Pre:  IIII jjjj     WREG =      jjjj IIII
    andlw   0xF0                  ; Pre:  jjjj IIII     WREG =      jjjj 0000
    xorwf   CRCH, f               ; Pre:  LLLL llll     CRCH =      MMMM llll
    swapf   CRCL, w               ; Pre:  IIII jjjj     WREG =      jjjj IIII
    rlncf   WREG, w               ; Pre:  jjjj IIII     WREG =      jjjI IIIj
    xorwf   CRCH, f               ; Pre:  MMMM llll     CRCH =      XXXN mmmm
    andlw   b'11100000'           ; Pre:  jjjI IIIj     WREG =      jjj0 0000
    xorwf   CRCH, f               ; Pre:  jjj0 0000     CRCH =      MMMN mmmm
    xorwf   CRCL, f               ; Pre:  MMMN mmmm     CRCL =      JJJI jjjj
    return

; ***********************************************
; Commands
; ***********************************************

; Provides information about the Bootloader to the host PC software.
BootInfoBlock:
    db      low(BOOTBLOCKSIZE), high(BOOTBLOCKSIZE)
    db      MAJOR_VERSION, MINOR_VERSION
;    db      0xFF, 0x84             ; command mask : family id Q10
    db      0xFF, 0x20             ; command mask : family id K40
    db      low(BootloaderStart), high(BootloaderStart)
    db      upper(BootloaderStart), 0 
BootInfoBlockEnd:

; In:   <STX>[<0x00>]<CRCL><CRCH><ETX>
; Out:  <STX><BOOTBYTESL><BOOTBYTESH><VERL><VERH><STARTBOOTL><STARTBOOTH><STARTBOOTU><0x00><CRCL><CRCH><ETX>
BootloaderInfo:
    movlw   low(BootInfoBlock)
    movwf   TBLPTRL
    movlw   high(BootInfoBlock)
    movwf   TBLPTRH
    movlw   upper(BootInfoBlock)
    movwf   TBLPTRU

    movlw   (BootInfoBlockEnd - BootInfoBlock)
    movwf   DATA_COUNTL
    clrf    DATA_COUNTH
    ;; fall through to ReadFlash code -- send Bootloader Information Block from FLASH.

; In:   <STX>[<0x01><ADDRL><ADDRH><ADDRU><0x00><BYTESL><BYTESH>]<CRCL><CRCH><ETX>
; Out:  <STX>[<DATA>...]<CRCL><CRCH><ETX>
ReadFlash:
    tblrd   *+                  ; read from FLASH memory into TABLAT
    movf    TABLAT, w
    rcall   SendEscapeByte
    rcall   AddCrc

    decf    DATA_COUNTL, f      ; decrement counter
    movlw   0
    subwfb  DATA_COUNTH, f

    movf    DATA_COUNTL, w      ; DATA_COUNTH:DATA_COUNTH == 0?
    iorwf   DATA_COUNTH, w
    bnz     ReadFlash           ; no, loop
    bra     SendChecksum        ; yes, send end of packet

; In:   <STX>[<0x02><ADDRL><ADDRH><ADDRU><0x00><BLOCKSL><BLOCKSH>]<CRCL><CRCH><ETX>
; Out:  <STX>[<CRCL1><CRCH1>...<CRCLn><CRCHn>]<ETX>
VerifyFlash:
    tblrd   *+
    movf    TABLAT, w    
    rcall   AddCrc

    movf    TBLPTRL, w          ; have we crossed into the next block?
#if ERASE_FLASH_BLOCKSIZE > .255
    bnz     VerifyFlash
    movf    TBLPTRH, w
    andlw   high(ERASE_FLASH_BLOCKSIZE-1)
#else
    andlw   (ERASE_FLASH_BLOCKSIZE-1)    
#endif
    bnz     VerifyFlash

    movf    CRCL, w
    call    SendEscapeByte
    movf    CRCH, w
    call    SendEscapeByte

    decf    DATA_COUNTL, f      ; decrement counter
    movlw   0
    subwfb  DATA_COUNTH, f

    movf    DATA_COUNTL, w      ; DATA_COUNTH:DATA_COUNTH == 0?
    iorwf   DATA_COUNTH, w
    bnz     VerifyFlash         ; no, loop
    bra     SendETX             ; yes, send end of packet

#ifdef SOFTWP
    reset                       ; this code -should- never be executed, but 
    reset                       ; just in case of errant execution or buggy
    reset                       ; firmware, these reset instructions may protect
    reset                       ; against accidental erases.
#endif

; In:   <STX>[<0x03><ADDRL><ADDRH><ADDRU><0x00><PAGESL>]<CRCL><CRCH><ETX>
; Out:  <STX>[<0x03>]<CRCL><CRCH><ETX>
EraseFlash:
;//<editor-fold defaultstate="open" desc="SOFTWP">
#ifdef SOFTWP
  #define ERASE_ADDRESS_MASK  (~(ERASE_FLASH_BLOCKSIZE-1))
  #if upper(ERASE_ADDRESS_MASK) != 0xFF
    movlw   upper(ERASE_ADDRESS_MASK)    ; force starting address to land on a FLASH Erase Block boundary
    andwf   TBLPTRU, f
  #endif
  #if high(ERASE_ADDRESS_MASK) != 0xFF
    movlw   high(ERASE_ADDRESS_MASK)    ; force starting address to land on a FLASH Erase Block boundary
    andwf   TBLPTRH, f
  #endif
  #if low(ERASE_ADDRESS_MASK) != 0xFF
    movlw   low(ERASE_ADDRESS_MASK)     ; force starting address to land on a FLASH Erase Block boundary
    andwf   TBLPTRL, f
  #endif

    ; Verify Erase Address does not attempt to erase beyond the end of FLASH memory
    movlw   low(END_FLASH)
    subwf   TBLPTRL, w
    movlw   high(END_FLASH)
    subwfb  TBLPTRH, w
    movlw   upper(END_FLASH)
    subwfb  TBLPTRU, w
    bn      EraseEndFlashAddressOkay

    clrf    NVMCON1              ; inhibit writes for this block
    bra     NextEraseBlock      ; move on to next erase block
#endif ; end #ifdef USE_SOFTBOOTWP
;//</editor-fold>

EraseEndFlashAddressOkay:
;//<editor-fold defaultstate="collapsed" desc="USE_SOFTCONFIGWP">
#ifdef USE_SOFTCONFIGWP
    #ifdef CONFIG_AS_FLASH
    movlw   low(END_FLASH - ERASE_FLASH_BLOCKSIZE)
    subwf   TBLPTRL, w
    movlw   high(END_FLASH - ERASE_FLASH_BLOCKSIZE)
    subwfb  TBLPTRH, w
    movlw   upper(END_FLASH - ERASE_FLASH_BLOCKSIZE)
    subwfb  TBLPTRU, w
    bn      EraseConfigAddressOkay

    clrf    NVMCON1              ; inhibit writes for this block
    bra     NextEraseBlock      ; move on to next erase block

EraseConfigAddressOkay:
    #endif ; end CONFIG_AS_FLASH
#endif ; end USE_SOFTCONFIGWP
;//</editor-fold>

;//<editor-fold defaultstate="open" desc="USE_SOFTBOOTWP">
#ifdef USE_SOFTBOOTWP
    movlw   low(BOOTLOADER_ADDRESS)
    subwf   TBLPTRL, w
    movlw   high(BOOTLOADER_ADDRESS)
    subwfb  TBLPTRH, w
    movlw   upper(BOOTLOADER_ADDRESS)
    subwfb  TBLPTRU, w
    bn      EraseAddressOkay

    movlw   low(BOOTLOADER_ADDRESS + BOOTBLOCKSIZE)
    subwf   TBLPTRL, w
    movlw   high(BOOTLOADER_ADDRESS + BOOTBLOCKSIZE)
    subwfb  TBLPTRH, w
    movlw   upper(BOOTLOADER_ADDRESS + BOOTBLOCKSIZE)
    subwfb  TBLPTRU, w
    bnn     EraseAddressOkay

#ifdef __P18FF27Q10
    clrf    NVMCON0              ; inhibit writes for this block
#endif
    bra     NextEraseBlock      ; move on to next erase block

    reset                       ; this code -should- never be executed, but 
    reset                       ; just in case of errant execution or buggy
    reset                       ; firmware, these reset instruction may protect
    reset                       ; against accidental writes.
#endif
;//</editor-fold>

EraseAddressOkay:

    ;rcall   StartWrite          ; erase the page
    rcall   StartErase          ; erase the page

NextEraseBlock:
    ; Decrement address by erase block size
#if ERASE_FLASH_BLOCKSIZE >= .256
    movlw   high(ERASE_FLASH_BLOCKSIZE)
    subwf   TBLPTRH, F
    clrf    WREG
    subwfb  TBLPTRU, F
#else
    movlw   ERASE_FLASH_BLOCKSIZE
    subwf   TBLPTRL, F
    clrf    WREG
    subwfb  TBLPTRH, F
    subwfb  TBLPTRU, F
#endif

    decfsz  DATA_COUNTL, F
    bra     EraseFlash    
    bra     SendAcknowledge     ; All done, send acknowledgement packet

#ifdef SOFTWP
    reset                       ; this code -should- never be executed, but 
    reset                       ; just in case of errant execution or buggy
    reset                       ; firmware, these reset instructions may protect
    reset                       ; against accidental writes.
#endif

; In:   <STX>[<0x04><ADDRL><ADDRH><ADDRU><0x00><BLOCKSL><DATA>...]<CRCL><CRCH><ETX>
; Out:  <STX>[<0x04>]<CRCL><CRCH><ETX>
WriteFlash:
;//<editor-fold defaultstate="open" desc="SOFTWP">
#ifdef SOFTWP
  #define WRITE_ADDRESS_MASK (~(WRITE_FLASH_BLOCKSIZE-1))
  #if upper(WRITE_ADDRESS_MASK) != 0xFF
    movlw   upper(WRITE_ADDRESS_MASK)    ; force starting address to land on a FLASH Write Block boundary
    andwf   TBLPTRU, f
  #endif
  #if high(WRITE_ADDRESS_MASK) != 0xFF
    movlw   high(WRITE_ADDRESS_MASK)    ; force starting address to land on a FLASH Write Block boundary
    andwf   TBLPTRH, f
  #endif
  #if low(WRITE_ADDRESS_MASK) != 0xFF
    movlw   low(WRITE_ADDRESS_MASK)     ; force starting address to land on a FLASH Write Block boundary
    andwf   TBLPTRL, f
  #endif

    ; Verify Write Address does not attempt to write beyond the end of FLASH memory
    movlw   low(END_FLASH)
    subwf   TBLPTRL, w
    movlw   high(END_FLASH)
    subwfb  TBLPTRH, w
    movlw   upper(END_FLASH)
    subwfb  TBLPTRU, w
    bn      WriteEndFlashAddressOkay

    clrf    NVMCON1              ; inhibit writes for this block
    bra     LoadHoldingRegisters; fake the write so we can move on to real writes
#endif ; end #ifdef SOFTWP
;//</editor-fold>

WriteEndFlashAddressOkay:
;//<editor-fold defaultstate="collapsed" desc="USE_SOFTCONFIGWP">
#ifdef USE_SOFTCONFIGWP
    #ifdef CONFIG_AS_FLASH
    movlw   low(END_FLASH - ERASE_FLASH_BLOCKSIZE)
    subwf   TBLPTRL, w
    movlw   high(END_FLASH - ERASE_FLASH_BLOCKSIZE)
    subwfb  TBLPTRH, w
    movlw   upper(END_FLASH - ERASE_FLASH_BLOCKSIZE)
    subwfb  TBLPTRU, w
    bn      WriteConfigAddressOkay

    clrf    NVMCON1              ; inhibit writes for this block
    bra     LoadHoldingRegisters; fake the write so we can move on to real writes

WriteConfigAddressOkay:
    #endif ; end CONFIG_AS_FLASH
#endif ; end USE_SOFTCONFIGWP
;//</editor-fold>

;//<editor-fold defaultstate="open" desc="USE_SOFTBOOTWP">
#ifdef USE_SOFTBOOTWP
    movlw   low(BOOTLOADER_ADDRESS)
    subwf   TBLPTRL, w
    movlw   high(BOOTLOADER_ADDRESS)
    subwfb  TBLPTRH, w
    movlw   upper(BOOTLOADER_ADDRESS)
    subwfb  TBLPTRU, w
    bn      WriteAddressOkay

    movlw   low(BOOTLOADER_ADDRESS + BOOTBLOCKSIZE)
    subwf   TBLPTRL, w
    movlw   high(BOOTLOADER_ADDRESS + BOOTBLOCKSIZE)
    subwfb  TBLPTRH, w
    movlw   upper(BOOTLOADER_ADDRESS + BOOTBLOCKSIZE)
    subwfb  TBLPTRU, w
    bnn     WriteAddressOkay

    clrf    NVMCON1                      ; inhibit writes for this block
    bra     LoadHoldingRegisters        ; fake the write so we can move on to real writes

    reset                       ; this code -should- never be executed, but 
    reset                       ; just in case of errant execution or buggy
    reset                       ; firmware, these reset instruction may protect
    reset                       ; against accidental writes.
#endif
;//</editor-fold>

WriteAddressOkay:
    ;BSF     NVMCON0,NVMEN
    rcall   ReadHoldingRegisters ; Load sector holding registers

LoadHoldingRegisters:
    movff   POSTINC0, TABLAT    ; Load the holding registers
    ;pmwtpi                      ; Same as tblwt *+
    tblwt   *+

    movf    TBLPTRL, w          ; have we crossed into the next write block?
    andlw   (WRITE_FLASH_BLOCKSIZE-1)
    bnz     LoadHoldingRegisters; Not finished writing holding registers, repeat

    tblrd   *-                  ; Point back into the block to write data
    rcall   StartWrite          ; initiate a page write
    tblrd   *+                  ; Restore pointer for loading holding registers with next block
    rcall   ReadHoldingRegisters ; Load sector holding registers

    decfsz  DATA_COUNTL, F      
    bra     WriteFlash          ; Not finished writing all blocks, repeat
    bra     SendAcknowledge     ; all done, send ACK packet

; In:   <STX>[<0x05><ADDRL><ADDRH><0x00><0x00><BYTESL><BYTESH>]<CRCL><CRCH><ETX>
; Out:  <STX>[<DATA>...]<CRCL><CRCH><ETX>
ReadEeprom:
#ifdef __18F27Q10
    bcf     NVMCON1,NVMREG0,A     ; point to EEPROM
    bcf     NVMCON1,NVMREG1,A     ; access EEPROM
    bsf     NVMCON1,RD          ; Issue EE Read
    movf    NVMDAT, w           ; WREG = EEPROM byte
    rcall   SendEscapeByte
    rcall   AddCrc

    incf    NVMADRL             ; Increment EEPROM pointer
    bnc     $+4
    incf    NVMADRH

    decf    DATA_COUNTL, f      ; decrement counter
    movlw   0
    subwfb  DATA_COUNTH, f

    movf    DATA_COUNTL, w      ; DATA_COUNTH:DATA_COUNTH == 0?
    iorwf   DATA_COUNTH, w
    bnz     ReadEeprom          ; no, loop
    bra     SendChecksum        ; yes, send end of packet
#endif

    bra     SendAcknowledge     ; all done, send ACK packet


; In:   <STX>[<0x06><ADDRL><ADDRH><0x00><0x00><BYTESL><BYTESH><DATA>...]<CRCL><CRCH><ETX>
; Out:  <STX>[<0x06>]<CRCL><CRCH><ETX>
WriteEeprom:
#ifdef __18F27Q10
    bcf     NVMCON1,NVMREG0,A     ; point to EEPROM
    bcf     NVMCON1,NVMREG1,A     ; access EEPROM
    movff   POSTINC0,NVMDAT       ; Load EEPROM byte
    bsf     NVMCON1,WREN          ; Write enable
    bcf     INTCON,GIE,A          ; disable interrupts
    movlw   0x55
    movwf   NVMCON2,A
    movlw   0xAA
    movwf   NVMCON2,A
    bsf     NVMCON1,WR,A          ; Start write
    ; Wait for write to complete
    btfsc   NVMCON1,WR
    bra     $-1
    bsf     INTCON,GIE,A          ; enable interrupts
    bcf     NVMCON1,WREN          ; disable writes

    incf    NVMADRL             ; Increment EEPROM pointer
    bnc     $+4
    incf    NVMADRH

    decf    DATA_COUNTL, f      ; decrement counter
    movlw   0
    subwfb  DATA_COUNTH, f

    movf    DATA_COUNTL, w      ; DATA_COUNTH:DATA_COUNTH == 0?
    iorwf   DATA_COUNTH, w
    bnz     EeWriteLoop          ; no, loop
#endif

    bra     SendAcknowledge     ; all done, send ACK packet

 
; In:   <STX>[<0x07><ADDRL><ADDRH><ADDRU><0x00><BYTES><DATA>...]<CRCL><CRCH><ETX>
; Out:  <STX>[<0x07>]<CRCL><CRCH><ETX>
;//<editor-fold defaultstate="collapsed" desc="CONFIG_AS_FLASH">
#ifndef CONFIG_AS_FLASH     ; J flash devices store config words in FLASH, so no need for this code
    #ifndef USE_SOFTCONFIGWP
WriteConfig:
    movlw   b'11000100'
    movwf   NVMCON1
    tblrd   *               ; read existing value from config memory

WriteConfigLoop:
    movf    POSTINC0, w
    cpfseq  TABLAT          ; is the proposed value already the same as existing value?
    rcall   TableWriteWREG  ; write config memory only if necessary (save time and endurance)
    tblrd   +*              ; increment table pointer to next address and read existing value
    decfsz  DATA_COUNTL, F
    bra     WriteConfigLoop ; If more data available in packet, keep looping

    bra     SendAcknowledge ; Send acknowledge
    #endif ; end #ifndef USE_SOFTCONFIGWP
#endif ; end #ifndef CONFIG_AS_FLASH
;//</editor-fold>
    
;************************************************

; ***********************************************
; Send an acknowledgement packet back
;
; <STX><COMMAND><CRCL><CRCH><ETX>

; Some devices only have config words as FLASH memory. Some devices don't have EEPROM.
; For these devices, we can save code by jumping directly to sending back an
; acknowledgement packet if the PC application erroneously requests them.
#ifdef CONFIG_AS_FLASH
WriteConfig:
#else
  #ifdef USE_SOFTCONFIGWP
WriteConfig:
  #endif
#endif ; end #ifdef CONFIG_AS_FLASH


SendAcknowledge:
    clrf    NVMCON1              ; inhibit write cycles to FLASH memory

    movf    COMMAND, w
    rcall   SendEscapeByte      ; Send only the command byte (acknowledge packet)
    rcall   AddCrc

SendChecksum:
    movf    CRCL, W
    rcall   SendEscapeByte

    movf    CRCH, W
    rcall   SendEscapeByte

SendETX:
    movlw   ETX             ; Send stop condition
    rcall   SendHostByte

    bra     WaitForHostCommand
; *****************************************************************************




; *****************************************************************************
; Write a byte to the serial port while escaping control characters with a DLE
; first.
SendEscapeByte:
    movwf   TXDATA          ; Save the data
 
    xorlw   STX             ; Check for a STX
    bz      WrDLE           ; No, continue WrNext

    movf    TXDATA, W       
    xorlw   ETX             ; Check for a ETX
    bz      WrDLE           ; No, continue WrNext

    movf    TXDATA, W       
    xorlw   DLE             ; Check for a DLE
    bnz     WrNext          ; No, continue WrNext

WrDLE:
    movlw   DLE             ; Yes, send DLE first
    rcall   SendHostByte

WrNext:
    movf    TXDATA, W       ; Then send STX

SendHostByte:
    clrwdt
    btfss   UxPIR, UxTXIF      ; Write only if TXREG is ready
    bra     $-2
    
    movwf   UxTXREG           ; Start sending

    return
; *****************************************************************************




; *****************************************************************************
ReadHostByte:
    btfsc   UxRCSTA, OERR       ; Reset on overun
    reset

WaitForHostByte:
    clrwdt
    banksel PIR3
    btfss   PIR3, UxRCIF       ; Wait for data from RS232
    bra     WaitForHostByte

    movf    UxRCREG, W          ; Save the data
    movwf   RXDATA
 
    return
; *****************************************************************************

    reset                       ; this code -should- never be executed, but 
    reset                       ; just in case of errant execution or buggy
    reset                       ; firmware, these instructions may protect
    clrf    NVMCON1              ; against accidental erase/write operations.

; *****************************************************************************
; Unlock and start the write or erase sequence.
TableWriteWREG:
    movwf   TABLAT
    tblwt   *

; *****************************************************************************
; Modified Jan. 12, 2021. MAF
StartWrite:
#ifdef __18F27Q10
    clrwdt

    bcf     INTCON,GIE,A      ; Disable interrupts
    bsf     NVMCON0,NVMEN,A       ; Enable Program FLash Memory
    movlw   0xDD            ; Unlock sector write to flash
    movwf   NVMCON2,A
    movlw   0x22
    movwf   NVMCON2,A
    bsf     NVMCON1,SECWR,A    ; Start the write
    nop
    bcf     NVMCON0,NVMEN,A       ; Disable Program FLash Memory
    bsf     INTCON,GIE,A      ; Enable interrupts
#endif

#ifdef __18F27K40
    bcf     NVMCON1,NVMREG0,A     ; point to Program Flash Memory
    bsf     NVMCON1,NVMREG1,A     ; access Program Flash Memory
    bsf     NVMCON1,WREN,A        ; enable write to memory
    bcf     NVMCON1,FREE,A        ; enable write to memory
    bcf     INTCON,GIE,A          ; disable interrupts
    movlw   0x55
    movwf   NVMCON2,A
    movlw   0xAA
    movwf   NVMCON2,A
    bsf     NVMCON1,WR,A          ; Start erase (CPU stalls)
    bsf     INTCON,GIE,A          ; re-enable interrupts
    bcf     NVMCON1,WREN,A        ; disable writes to memory
#endif

    return

; *****************************************************************************
; Added Jan. 18, 2021. MAF
; Read a sector block content into the holding registers.
; The TBLPTR should hold the first byte so transfer TBLPTR registers to
; NVMADR registers
ReadHoldingRegisters:
#ifdef __18F27Q10
    movff   TBLPTRU,NVMADRU
    movff   TBLPTRH,NVMADRH
    ;movff   TBLPTRL,NVMADRL
    clrf    NVMADRL,A
    bsf     NVMCON0,NVMEN,A       ; Enable Program FLash Memory
    movlw   0xBB            ; Unlock
    movwf   NVMCON2,A
    movlw   0x44
    movwf   NVMCON2,A
    bsf     NVMCON1,SECRD,A  ; 
    nop
    bcf     NVMCON0,NVMEN,A       ; Disable Program FLash Memory
#endif

#ifdef __18F27K40
    ; The PIC18F27K40 doesn't have a read holding registers command. Data
    ; in PFM needs to be read into a SRAM buffer, then written to the
    ; write latch holding registers. The original bootloader just wrote to the
    ; holding registers without reading them into a buffer first and modifying
    ; the data there.
#endif

    return

; *****************************************************************************
; Added Jan. 18, 2021. MAF
; The address to erase is passed in the TBLPTR registers. Transfer that value
; to the NVMADR registers and make sure NVMADRL is zero.
; 
StartErase:
#ifdef __18F27Q10
    movff   TBLPTRU,NVMADRU
    movff   TBLPTRH,NVMADRH
    ;movff   TBLPTRL,NVMADRL
    clrf    NVMADRL
    clrwdt
    bsf     NVMCON0,NVMEN,A       ; Enable Program FLash Memory
    movlw   0xCC            ; Unlock
    movwf   NVMCON2,A
    movlw   0x33
    movwf   NVMCON2,A
    bsf     NVMCON1,SECER,A  ; Start the erase (10 ms)
    nop
    bcf     NVMCON0,NVMEN,A       ; Disable Program FLash Memory
#endif

#ifdef __18F27K40
    bcf     NVMCON1,NVMREG0,A     ; point to Program Flash Memory
    bsf     NVMCON1,NVMREG1,A     ; access Program Flash Memory
    bsf     NVMCON1,WREN,A        ; enable write to memory
    bsf     NVMCON1,FREE,A        ; enable block erase operation
    bcf     INTCON,GIE,A          ; disable interrupts
    movlw   0x55
    movwf   NVMCON2,A
    movlw   0xAA
    movwf   NVMCON2,A
    bsf     NVMCON1,WR,A          ; Start erase (CPU stalls)
    bsf     INTCON,GIE,A          ; re-enable interrupts
    bcf     NVMCON1,WREN,A        ; disable writes to memory
#endif

    return
; *****************************************************************************

