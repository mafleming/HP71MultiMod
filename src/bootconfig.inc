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

#define USE_SOFTBOOTWP          ; enable software boot block write protection
;#define USE_SOFTCONFIGWP        ; enable software config words write protection

; Bootloader must start at the beginning of a FLASH Erase Block. If unspecified,
; bootloader will automatically be located at the end of program memory address space.
#define BOOTLOADER_ADDRESS   0  ; bootloader at beginning, application start/ISR vectors require remapping

; For Bootloader located at program memory address 0, the application firmware must 
; provide remapped reset and interrupt vectors outside of the Boot Block. The following 
; #defines tell the bootloader firmware where application entry points are to be expected:
#define AppVector           0x0a00   ; application start up code should be located here.
#define AppHighIntVector    0x0900   ; application high priority interrupt should be located here
#define AppLowIntVector     0x0980   ; application low priority interrupt should be located here

; Define UART pins and registers. 
; Modify the following lines if you want to use a different UART module.
;
; Note: If your UART's RX pin happens to be multiplexed with analog ANx input
;	functionality, you may need to edit the "preprocess.inc" DigitalInput
;	macro. Code there needs to enable the digital input buffer (refer to
;	ADC chapter of your device's datasheet).
    #define UxSPBRG         SP1BRG
    #define UxSPBRGH        SP1BRGH
    #define UxRCSTA         RC1STA
    #define UxTXSTA         TX1STA
    #define UxRCREG         RC1REG
    #define UxTXREG         TX1REG
    #define UxPIR           PIR3
    #define UxRCIF          RC1IF
    #define UxTXIF          TX1IF
    #define UxBAUDCON       BAUD1CON

    #define RXPORT          PORTC   ; RX on RC7 is used by default for most PIC18's.
    #define RXPIN           .7

; If you get linker errors complaining "can not fit the absolute section," you might want to
; increase BOOTLOADERSIZE below or set the BOOTLOADER_ADDRESS above to a smaller address number.

; Because we need to know the total size of the bootloader before the assembler has finished
; compiling the source code, we have to estimate the final bootloader size and provide it
; here as BOOTLOADERSIZE. This number is in bytes (twice the instruction word count). 
;
; If you see the bootloader is reserving more FLASH memory than it really needs (you'll
; see a bunch of FFFF/NOP instructions at the end of the bootloader memory region),
; you can try reducing BOOTLOADERSIZE.
#define BOOTLOADERSIZE  .708

#define MAJOR_VERSION   .1              ; Bootloader Firmware Version
#define MINOR_VERSION   .5
