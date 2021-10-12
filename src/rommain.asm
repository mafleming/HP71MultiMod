;*******************************************************************************
;                                                                              *
;    Filename:      rommain.asm                                                *
;    Date:          July 25, 2020                                              *
;    File Version:  1.0                                                        *
;    Author:        Mark A. Fleming                                            *
;    Company:                                                                  *
;    Description:   Emulate HP-71B ROM memory                                  *
;                                                                              *
;*******************************************************************************
;    Notes:                                                                    *
;      7/25/2020, Couldn't get relocatable mode directives to work so I set    *
;      mpasm option to work in absolute mode.                                  *
;      7/28/2020, By default, RAM access is by the Bank Select Register,       *
;      denoted by 0. I want the Access Bank mode which requires a 1 instead.   *
;      Anyplace that references an SFR, including WREG, must have a trailing   *
;      ,0 (here and in macro.inc)                                              *
;      8/7/2020, Annotate code with number of instruction cycles taken in      *
;      each half of a clock cycle. At 650KHz clock speed, there are only       *
;      770 ns per cycle half. At a PIC clock speed of 64 MHz that means just   *
;      12 instruction cycles per bus clock cycle half.                         *
;      8/12/2020, Rework how TBLPTR is used based on actual bus operations.    *
;      Precompute TBLPTR whenever PC or DP is loaded. When switching from      *
;      DP to PC, save TBLPTR and load new TBLPTR value.                        *
;      8/13/2020, Bus timing is critical in regard to when and how long a      *
;      device should drive the command bus. For the ID and two READ commands   *
;      I'm driving the bus immediately after the falling edge of STRn and      *
;      releasing it immediately after the rising edge of STRn. Hopefully I'm   *
;      within the limits of Tacc and Toh.                                      *
;                                                                              *
;*******************************************************************************
;                                                                              *
;    Revision History:                                                         *
;    1.0  25-July-2020                                                         *
;    2.0  1-October-2020                                                         *
;*******************************************************************************


;*******************************************************************************
; Theory Of Operation
;  The following sections provide a brief summary of how the HP-71 communicates
;  with devices plugged into it and the way this software emulates a ROM plugin
;  in particular.
;  
; Program Memory Map
;  0 0000 - 0 0007   RESET Vector
;  0 0008 - 0 0017   High Priority Interrupt Vector
;  0 0018 - 0 0027   Low Priority Interrupt Vector
;  0 0030 - 0 07FF   Primary Bootloader (memory protected)
;  0 0800 - 0 0FFF   Secondary Bootloader
;  0 1000 - 0 10FF   Program Constants
;  0 1100 - 0 117F   High Priority Interrupt Service Routine
;  0 1180 - 0 11FF   Low Priority Interrupt Service Routine
;  0 1200 - 0 3FFF   Application Code
;  0 4000 - 0 7FFF   ROM Block 1
;  0 8000 - 0 BFFF   ROM Block 2
;  0 C000 - 0 FFFF   ROM Block 3
;  1 0000 - 1 3FFF   ROM Block 4
;  1 4000 - 1 7FFF   ROM Block 5
;  1 8000 - 1 BFFF   ROM Block 6
;  1 C000 - 1 FFFF   ROM Block 7
;  
; Special Function Register Usage
;  
;  BSR E Addressed   BSR F Addressed   Access Bank Addressable
;  EA1    INT0PPS    F0A    IOCAF      F81    NVMCON1
;  EA2    INT1PPS    F0B    IOCAN      F82    NVMCON2
;  EB5    RX1PPS     F0C    IOCAP      F83    LATA
;  EBA    IPR0       F0D    INLVLA     F84    LATB
;  EC2    PIE0       F0E    SLRCONA    F85    LATC
;  ECA    PIR0       F0F    OSCONA     F88    TRISA
; *ECD    PIR3       F10    WPUA       F89    TRISB
; *ED7    CPUDOZE    F11    ANSELA     F8A    TRISC
;  ED8    OSCCON1    F15    INLVLB     F8D    PORTA
;  EDA    OSCCON3    F16    SLRCONB    F8E    PORTB
;  EDC    OSCEN      F17    ODCONB     F8F    PORTC
;  EDD    OSCTUNE    F18    WPUB       F99    RC1REG
;  EDE    OSCFRQ     F19    ANSELB     F9A    TX1REG
;  EE1    PMD0       F1D    INLVLC     F9B    SP1BRGL
;  EE2    PMD1       F1E    SLRCONC    F9C    SP1BRGH
;  EE3    PMD2       F1F    ODCONC     F9D    RC1STA
;  EE4    PMD3       F20    WPUC       F9E    TX1STA
;  EE5    PMD4       F21    ANSELC     F9F    BAUD1CON
;  EE6    PMD5       F2D    WPUE       FD8    STATUS
;  EFD    RC6PPS                       FD9    FSR2
;                                      FD9    FSR2L
;                                      FDB    PLUSW2
;                                      FE1    FSR1
;                                      FE1    FSR1L
;                                      FE3    PLUSW1
;                                      FE8    WREG
;                                      FE9    FSR0
;                                      FE9    FSR0L
;                                      FEB    PLUSW0
;                                      FEE    POSTINC0
;                                      FEF    INDF0
;                                      FF2    INTCON
;                                      FF3    PRODL
;                                      FF5    TABLAT
;                                      FF6    TBLPTRL
;                                      FF7    TBLPTRH
;                                      FF8    TBLPTRU
;                                      FF9    PCL
;                                      FFA    PCLATH
;                                      FFD    TOSL
;                                      FFE    TOSH
;  
;  Most of the Special Function Registers outside of the Access Bank addressing
;  mode range are only referenced during initialization. These need an explicit
;  BSR addressing mode bit set in instructions.
;  
;  Only two of the Special Function Registers (SFRs) in Bank E, marked with an
;  asterisk, need the 'banksel' command to switch to access them. All of the
;  commonly used SFRs in Bank F need an explicit Access Bank addressing mode
;  bit set in an instruction.
;  
; Pointer Usage
;  There are four pointers used in the emulator software; The TBLPTR pointer
;  into Program Flash Memory and the three pointers into data SRAM, FSR0, FSR1,
;  and FSR2. All four are used during initialization. During ROM Emulator
;  operation, the pointers in use are
;  
;  TBLPTR  Used to address PFM byte holding the next nibble to return by a
;          PCREAD or DPREAD command. The address is computed by the LOADPC or
;          LOADDP command and s saved after every use to locations PPTR or DPTR.
;  FSR1    Used by the PCWRITE and DPWRITE functions to write data to the
;          command buffer, starting at ROMNUM, and holding up to 16 nibbles
;  FSR2    Points to the Mapping Table MAPTAB, used during the mapping process
;          from the 20-bit Saturn address to the 17-bit PFM address.
;  
;  
; PIC18F Hardware Operation
;  The PIC18F used by this software has a 64 MHz internal clock that is
;  accurate to 1%. The CPU can execute 16 million instruction cycles per second
;  and the majority of instructions require only one cycle. The HP-71 CPU
;  operates at a nominal clock speed of 625 KHz, meaning about 25 instructions
;  per host clock cycle. As a hard real-time system, this software must perform
;  any required operation within the specified time limits, or fail.
;  
;  The PIC18F controller is connected to a 4-bit wide bidirectional command/data
;  bus and three control signals. Interrupts are used to speed response time in
;  place of spin-waits where timing is critical.
;  
; HP-71B Bus Operation
;  The authoritative source of information on the operation of the HP-71B
;  hardware can be found in the "Hardware Internal Design Specification for the
;  HP-71" from Hewlett Packard. A copy of the document can be found on a flash
;  drive from the Museum of HP Calculators. Consult the following web page
;  https://www.hpmuseum.org/cd/cddesc.htm
;  
; ROM Image Layout
;  The Program Flash Memory (PFM) of the PIC18F processor is organized as eight
;  8 KWord (16 KByte) blocks, for a total of 64 KWords (128 KBytes). Each PIC
;  instruction is one word (16-bits) in length. An important feature of this
;  mid-range controller is the ability to alter any location in flash on a byte
;  by byte basis. This allows the software to load ROM images or rewrite the
;  software itself without the need for a specialized programming device.
;  
;  ROM images are supported in four sizes; 16KB, 32KB, 48KB, and 64KB. The 16KB
;  PFM blocks can be thought of as seven 16KB "chips" into which a ROM image
;  can be placed. A ROM image can occupy one or more consecutive blocks
;  depending on its size. Each of the "chips" can be enumerated separately
;  with the ID string dividing the chips into sequences for each separate ROM
;  image. Nibble 3 of the ID string is used to denote the end of ROM sequnce and
;  distinguish one sequence from another.
;  
;  An alternative scheme is to directly encode the ROM size in the first ID
;  nibble. This would use a single table entry to encode 16K, 32K or 64K ROMs.
;  Either approach is supported, though the multi-chip approach is faster.
;  
; ROM Image Access
;  When the DP or PC register is loaded with an address, the software constructs
;  a pointer into PFM based on the register value. Subsequent reads are done
;  using the pointer if the register address is within the range of the ROM's
;  assigned base address. This is done by using the top five bits of the
;  register address to look up a value that is used in PFM addressing. If the
;  value is zero then the register does not address one of the seven 16KB PFM
;  blocks. Once the PFM pointer is constructed, it is saved across all nibble
;  reads. Importantly, this means the pointer-based reads can cross PFM block
;  boundaries, as would be expected with multi-chip ROM images. Boundary
;  crossing is not checked for, rather it is assumed ROM content would not
;  intentionally run off the end of a ROM resulting in invalid memory accesses.
;  
; Application Task Organization
;  The ROM emulator application can be thought of as a set of tasks whose
;  execution is controlled by interrupt dispatch or direct transfer of control.
;  In reality of course, these are really just States in a State Machine.
;  Nonetheless, this documentation will continue with the fiction of tasks.
;  These tasks are
;  
;  - Initialize Device. Initiated by the low priority interrupt generated by the
;    rising edge of the Daisy-In (Din) control line. Disables interrupts,
;    responds to the ID and CONFIGURE commands, then enables interrupts and
;    transfers control to the Idle task.
;  
;  - Command Dispatch. Initiated by the high priority interrupt generated by the
;    falling edge of CDn. A jump table is used to vector to the right code
;    segment based on command value and ROM size.
;  
;  - Idle. When the emulator is not loading a register or serving ROM content
;    it spends its time in the Idle task. The task can reduce power usage or
;    check the serial port for input from the user. A software counter is
;    started each time Idle is entered. The timer will expire after 2-1/2
;    minutes and the CPU will enter sleep mode to save power (~6 uA drain).
;  
; Command Processing
;  A command cycle begins when the CDn signal falls, then the STRn strobe clock
;  falls and then rises, marking a write cycle for the command. The falling
;  edge of CDn generates an interrupt that directs processor control to a
;  command dispatch routine. The interrupt was necessary because a command cycle
;  can begin in the midst of a series of Read or Write cycles. Timing
;  constraints proved too tight to simple check the state of the CDn signal
;  after a spin-wait on STRn going low.
;  
; Timing Considerations
;  As previously mentioned, all processing must complete during a 71B host
;  cycle. The first half of a cycle is marked by STRn going low and the second
;  half by STRn going high. Data from the CPU or ROM is stable by STRn rise
;  and is sampled there. The timing diagrams in IDS section 9 implies ROM data
;  must be stable within 200 ns of STRn fall, but this is not necessary for
;  ROM data output. On the other hand, early Saturn CPUs took considerably
;  longer before output data was stable, which caused invalid reads if data was
;  sample too early before STRn rise.
;  
;  A spin-wait macro is used to wait for STRn to go high or low, marking entry
;  into one of the host half-cycles. This spin-wait can be as little as 2
;  instruction cycles (IC) long or as much as 4 IC depending on whether the
;  STRn state is true or false at the time it is sampled. This introduces some
;  indeterminism or jitter in timing.
;  
;  Each of the spin-wait macros is annotated with the number of PIC instruction
;  cycles which follows it before the next spin-wait macro. These annotations
;  help in determining if processing is within cycle boundaries. Occasionally
;  the first and second half-cycles are "merged" by commenting out the spin-wait
;  for STRn rise.
;  
; Timing Failure Points
;  A 71B host timing cycle is long enough for about 25 PIC instruction cycles
;  at the nominal host frequency. There is natural variation from machine to
;  machine which could reduce the number of PIC instructions that can be used.
;  
;  The CDn falling edge that marks the begining of an command cycle causes
;  an interrupt that could cut off PIC processing before the end of a host
;  cycle. A repetitive series of cycles, as in Read and Write cycles, needs to
;  leave some timing slack at the end of the second host half-cycle.
;  CDn falling edge occurs about two instruction cycles before the falling edge
;  of STRn.
;  
;  A Load DP or Load PC command can be followed by another instruction,
;  even perplexingly by a Read command. This means processing in the Load
;  command must complete and leave some slack at the end. One cannot just
;  assume the Load command will be followed by a dummy cycle and one or more
;  read cycles.
;  
;  Possible Timing Fault Points in the Code
;  
;  - LOADREG macro. The last cycle that reads the high nibble of an address has
;    its half-cycles merged, resulting in an instruction count of 2~4 + 19. A
;    CDn interrupt here could possibly result in TBLPTRU being incorrectly set.
;  Addressed Dec. 12, 2020: Reduced to 2~4 + 18. Still tight!
;  
;  - PCREAD/DPREAD routine. The main loop that handles a series of nibble reads
;    has its half-cycles merged. Instruction coult is 2~4 + 19/20. A CDn
;    interrupt would only cause the next unneeded nibble to be lost or the
;    branch to the top of the loop to not be executed.
;  
; User Interaction
;  When first powered on the software does not enumerate a ROM image. If a hard
;  configured ROM image is stored, it will always respond to a probe of its
;  content by the HP-71B. To enumerate any other ROM image, use the POKE
;  command and store any non-zero hex digit to address 2C000h. Turn the 71B off
;  then on again to make the ROM images available. If a value of zero is
;  written and power is cycled then all ROM images will be unavailable.
;  
;*******************************************************************************    


    TITLE "HP71B ROM Emulator"

;*******************************************************************************
; Conditional Compilation Configuration Settings
; 
; If using an external bootloader usch as the one in AN851 or AN1310, define
; both XTRNBOOT and SERMON.
; If an internal monitor is part of the build, define SERMON.
; 
;*******************************************************************************    
#define XTRNBOOT
#define SERMON

; My development working microcontroller
#ifdef __18F27Q10
#include p18f27q10.inc
    LIST P=PIC18F27Q10
#endif

; Substitute chip, better flash programming
#ifdef __18F27K40
#include p18f27k40.inc
    LIST P=PIC18F27K40
#endif

#ifndef XTRNBOOT
    #include config.inc
#endif
#include macros.inc

;*******************************************************************************
; System Constants
;*******************************************************************************    
    CONSTANT    cmdNOP=         0x0
    CONSTANT    cmdID=          0x1
    CONSTANT    cmdPCREAD=      0x2
    CONSTANT    cmdDPREAD=      0x3
    CONSTANT    cmdPCWRITE=     0x4
    CONSTANT    cmdDPWRITE=     0x5
    CONSTANT    cmdLOADPC=      0x6
    CONSTANT    cmdLOADDP=      0x7
    CONSTANT    cmdCONFIGURE=   0x8
    CONSTANT    cmdUNCONFIGURE= 0x9
    CONSTANT    cmdPOLL=        0xA
    CONSTANT    cmdRESERVED1=   0xB
    CONSTANT    cmdBUSCC=       0xC
    CONSTANT    cmdRESERVED2=   0xD
    CONSTANT    cmdSHUTDOWN=    0xE
    CONSTANT    cmdRESET=       0xF

    ; Constants associated with ROM configuration table
    CONSTANT    teID1=          0x00
    CONSTANT    teID2=          0x01
    CONSTANT    teID3=          0x02
    CONSTANT    teID4=          0x03
    CONSTANT    teID5=          0x04
    CONSTANT    teFLAG=         0x05
    CONSTANT    teADDR=         0x06
    CONSTANT    teBANK=         0x07
    CONSTANT    te16K=          0x0a
    CONSTANT    te32K=          0x09
    CONSTANT    te64K=          0x08
    CONSTANT    teEOM=          0x03
    CONSTANT    teLAST=         0x00
    CONSTANT    teHARD=         0x01

    ; Constants associated with ROM configuration nibble ROMNUM
    CONSTANT    cfMAIN=         .0
    CONSTANT    cfHIDDEN=       .1

    ; 7 ROMs (plus add one for MMIO address)
    CONSTANT    NROMS=          0x7
    ;; ROMLEN MUST BE EVEN!
    CONSTANT    ROMLEN=         0x8
    ; The table offset to first of two Hard ROM slots
    CONSTANT    HRDSLOT=        0x5
    ; The mask for the MMIO address
    CONSTANT    MMIOMASK=       0x0f

; EEPROM memory can be read using NVM registers or TBLPTR
; ORG 0x310000
;ROM1 DE 0x0a, 0x00, 0x01, 0x00, 0x08
    

;*******************************************************************************
; Variable Declarations
; ALL variables are in Bank 0
; For Access Bank addressing, variables must be in the range of 00 - 5Fh
; 
; Access Bank SPR's used in this program
; 
; 
; 
; 
;*******************************************************************************

CMD     EQU     0x00                ; Command register (nibble)
RDY     EQU     0x01                ; Module ready flag
ADDR    EQU     0x02                ; Configuration address (20 bits, 3 bytes)
PCREG   EQU     0x05                ; PC register (20 bits, 3 bytes)
DPREG   EQU     0x08                ; DP register (20 bits, 3 bytes)
;ROMBANK EQU     0x0b                ; Which of 8 PFM banks is active ROM
ROMSIZ  EQU     0x0c                ; Temporary used in initialization
MAPVAL  EQU     0x0d                ; Temporary used in initialization
ARANGE  EQU     0x0e                ; Address range bits 19 downto 15
DRANGE  EQU     0x0f                ; DP register range bits 19 downto 15
PRANGE  EQU     0x10                ; PC register range bits 19 downto 15
CNTR    EQU     0x11                ; General use counter
APTR    EQU     0x12                ; Not used except as scratch
DPTR    EQU     0x15                ; TBLPTR for DP register
PPTR    EQU     0x18                ; TBLPTR for PC register
IDSENT  EQU     0x1b                ; Flag that ID has been sent, ignore ID cmd
TEMP    EQU     0x1c                ; Temporary variable
MIOVLD  EQU     0x1d                ; Address is in MMIO address range
MIOADR  EQU     0x1e                ; MMIO register to read/write
ADIGIT  EQU     0x1f                ; Temporary location for a digit (ASCII 0-8)
ROMNUM  EQU     0x20                ; ROM Configuration nibble @ 2C000h
CMDBUF  EQU     0x21                ; MMIO (16 bytes)/Command Buffer (6 bytes)

ROMDAT  EQU     0x30                ; ROM configuration initialized on start
        ; 5 nibble address of Memory-mapped I/O device
MMIO   EQU     ROMDAT+ROMLEN*NROMS

MAPTBL  EQU     0xe0                ; Top 32 registers of page 0

DATABUF EQU     0x0100              ; Use SRAM page 1 for serial buffer
SECTBUF EQU     0x0200              ; Use SRAM page 2 for sector buffer

;//<editor-fold defaultstate="open" desc="No External Bootloader">
        IFNDEF  XTRNBOOT
;*******************************************************************************
; Protected Bootloader
;*******************************************************************************

;*******************************************************************************
; Reset Vector
;*******************************************************************************

RESVEC  ORG     0x0000              ; processor reset vector
        goto    START               ; go to beginning of program

;*******************************************************************************
; Interrupt Service Vectors
;*******************************************************************************
IV1     ORG     0x8
        goto    ISVHI
    
IV2     ORG     0x18
        goto    ISVLO

        ENDIF   ; end of #ifndef XTRNBOOT
;//</editor-fold>
;//<editor-fold defaultstate="open" desc="External Bootloader">
        IFDEF  XTRNBOOT
#include bootloader.inc
        ENDIF   ; end of #ifdef XTRNBOOT
;//</editor-fold>

;*******************************************************************************
; Configuration Constants
; Each of the first seven entries in this table describe a soft or hard ROM.
; Each entry consists of
;  Five nibble ID, Flag byte, Addr byte, Program Flash Memory Bank (ROMBANK)
;
; Soft ROMs are described in the first table entries, and they end when the
; Flag byte is non-zero.
; Each ID nibble is stored in a byte, starting with the first nibble.
; PFM Bank is between 1 and 7.
;
; Hard ROMs, if any, follow the last soft ROM entry. They use the Flag and Addr
; bytes.
;  The Flag byte indicates whether the entry is inactive (0) or active (ff).
;  The Addr byte is used to address the lookup table that defines where the
;  ROM appears in the Saturn address space. The values can be 0x1c & 0x1d for
;  base address E0000h or 0x00 & 0x01 for base address 00000h.
; 
; Found out that the number of DB bytes per ROM config string MUST BE EVEN!
; An odd length ends up padding the extra byte with zero.
; Size of constant section must be a multiple of sector size (128 Words,
; 256 bytes) so the sector can be erased before written to.
;*******************************************************************************
;CSECT   ORG 0x1000
CSECT   ORG 0x800
ROM1
#include ROMconfig.inc
        ORG 0x880
        data "Copyright 2021, Mark A. Fleming"
; ROMs enumerated according to size
;ROM1    DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x20, 1 ; 16K forth
;        DB  0x09, 0x01, 0x01, 0x00, 0x08, 0x00, 0x40, 2 ; 32K math2b
;        DB  0x09, 0x02, 0x01, 0x00, 0x08, 0xff, 0x80, 4 ; 32K jpc05
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0xff, 0x00, 4 ; Empty
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0xff, 0x00, 5 ; Empty
        ; Hard configured ROM must be in last two entries
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0xff, 0x1c, 6 ; 32K forthhrd
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0xff, 0x1d, 7 ; 32K forthhrd
;        DB  0x00, 0x00, 0x00, 0x0c, 0x02, 0x00, 0x00, 0 ; MMIO address
; ROMs enumerated as 16K chips
;ROM1    DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x20, 1 ; 16K forth
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 2 ; 32K math2b
;        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x60, 3 ; 32K math2b
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x00, 0x80, 4 ; 32K jpc05
;        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x01, 0xa0, 5 ; 32K jpc05
        ; Hard configured ROM must be in last two entries
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x1c, 6 ; 32K forthhrd
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x1d, 7 ; 32K forthhrd
;        DB  0x00, 0x00, 0x00, 0x0c, 0x02, 0x00, 0x00, 0 ; MMIO address

;*******************************************************************************
; ROM IMAGES
; ROM images begin in block 1, address 04000h and can occupy flash memory up to
; beginning address 1C000. A hard configured ROM could go anywhere, but by
; convention is placed in the last two blocks, addressed from 18000h to 1FFFFh.
;*******************************************************************************
;        org 0x04000
;#include forth.inc
;        org 0x08000
;#include math2b.inc
;        org 0x10000
;#include jpc05.inc
;        org 0x18000
;#include forthhrdfix.inc

;*******************************************************************************
; Interrupt Service Routines
;*******************************************************************************


;*******************************************************************************
; High Priority Interrupt Service Routine
; This ISR services a single interrupt source, the CDn signal that interrupts
; on its falling edge. The ISR replaces the top of stack return address with
; the address of the Command Dispatch task. That task reads the command nibble
; and dispatches control to the appropriate code routine.
; 
; Note: Two instruction cycles can be saved by placing the service routine
;   directly at the interrupt service vector, eliminating the two IC goto
;   instruction delay.
; 
; Latency
;   3/4 (response) + 2 (ISR goto) + 8 instruction cycles (13~14 IC)
;   There is a delay of ~125 ns between CDn fall and STRn fall, or 2 IC
; 
;*******************************************************************************
;        ORG     0x1100
        ORG     0x900
ISVHI
        ; How about POP, BRA CMDCYCLE ?
        movlw   high(CMDREAD)       ;Vector control to command processing
        movwf   TOSH
        movlw   low(CMDREAD)
        movwf   TOSL
        banksel PIR0
        bcf     PIR0,INT0IF,1       ; Clear interrupt flag
        retfie


;*******************************************************************************
; Low Priority Interrupt Service Routine
; This ISR can service more than one interrupt source. That source can be
; - Rising edge of the Daisy-In signal. Transfer control to the Initialize
;   Device task where interrupts are disabled and devices are configured
; - Other. Serial port receive buffer full or transmit buffer empty could be
;   handled here.
; 
; Note: Two instruction cycles can be saved by placing the service routine
;   directly at the interrupt service vector, eliminating the two IC goto
;   instruction delay.
; 
; Latency
;   3/4 (response) + 2 (ISR goto) + 8 instruction cycles (13~14 IC)
; 
;*******************************************************************************
;        ORG     0x1180
        ORG     0x980
ISVLO
        ; Din goes high
        movlw   high(INITDEV)       ;Vector control to device initialization
        movwf   TOSH
        movlw   low(INITDEV)
        movwf   TOSL
        banksel PIR0
        bcf     PIR0,INT1IF,1       ; Clear interrupt flag
        retfie


;*******************************************************************************
; MAIN PROGRAM AREA
;*******************************************************************************
;PSECT   ORG     0x1200
PSECT   ORG     0xa00
START
        ; Hardware initialization here
        call    INITMOD
        call    HARDRST
        DATAIN                      ; Should always default to DATAIN
        ;; Debug
        bcf     TRISA,6,0           ; Set RA6 as output
        bcf     PORTA,6,0           ; Clear flag

;*******************************************************************************
; INITIALIZE DEVICE TASK
; Synopsis
;  Control begins here on power-on reset and on the rising edge of the Daisy-In
;  interrupt. Interrupts are disabled and the task enumerates devices by
;  responding to a series of ID commands and CONFIGURE commands. Once all have
;  been enumerated, interrupts are enabled and control transferred to the IDLE
;  task. If there are no devices to enumerate then only the low priority
;  interrupt for Daisy-In is enabled and control is transferred to the IDLE
;  task.
; 
; Processing
;  - Disable interrupts while configuration of devices is performed.
;  - Initialize SRAM tables from Flash images.
;  - While Daisy-In (Din) is high, respond to the ID and CONFIGURE commands.
;    Ignore further ID commands when all ROMs have been enabled.
;  - Once all ROMs have been enumerated, check for and process a hard ROM, then
;    enable interrupts and transfer control to the IDLE task.
; 
; Note that enumeration will terminate when the Daisy-In line goes low. No check
; is made to see if all table entries have been processed. No check is made that
; the end of the table has been reached, so the table end marker must be set to
; avoid garbage IDs or an infinite loop of ID/CONFIGURE commands.
;*******************************************************************************
INITDEV
        banksel CMD
        bcf     INTCON,GIEH,0       ; High Priority Interrupt Disable
        bcf     INTCON,GIEL,0       ; Low Priority Interrupt Disable
        banksel PIR0
        bcf     PIR0,INT0IF,1       ; Clear interrupt flag
        bcf     PIR0,INT1IF,1       ; Clear interrupt flag
        banksel CMD
;*******************************************************************************
; EXPERIMENTAL!
; This code is used to assert & deassert the Halt signal to the Saturn CPU to
; allow the PIC enough time to recover from sleep and continue processing.
; Its purpose is to support a takeover ROM.
;*******************************************************************************
;        bcf     SIGLAT,Halt71,0     ; Clear HALT signal
;        bsf     SIGTRIS,Halt71,0    ; Disable HALT signal output driver
;*******************************************************************************
        FLAGLO
        call    INITVAR
        call    INITTAB
        movlw   NROMS               ; Don't scan beyond end of table
        movwf   CNTR                ; Limit number of table entries scanned
        lfsr    FSR0,ROMDAT         ; Point to first ROM entry

        movlw   0x00
        cpfsgt  ROMNUM              ; Skip if ROMNUM > 0
        bra     INIEXIT             ; A zero in ROMNUM unplugs all ROMs
                                    ; Should be EXITINI
        btfss   SIGPORT,Din,0       ; Only enumerate when Daisy-In is high
        bra     $-2                 ; This could be a hang until 71B turned on
ENUMROM
        NEGEDGE CDn
        NEGEDGE STRn
        ;NEGEDGE STRn               ; Command appears much later in older 71B
        POSEDGE STRn                ; Must sample as close as can to this edge
        BUSRD
        movwf   CMD                 ; Save command
        ;POSEDGE CDn
        movlw   cmdID
        cpfseq  CMD,0               ; Skip if ID
        bra     INIT2
        ; Execute ID command
        movlw   teID1
        BUSWR   PLUSW0
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        FLAGHI
        POSEDGE STRn                ; 2~4 + 4 instruction cycles
        DATAIN
        ;
        movlw   teID2
        BUSWR   PLUSW0
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn
        DATAIN
        ;
        movlw   teID3
        BUSWR   PLUSW0
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAIN
        ;
        movlw   teID4
        BUSWR   PLUSW0
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAIN
        ;
        movlw   teID5
        BUSWR   PLUSW0
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAIN
        FLAGLO
        movlw   teFLAG              ; Flag byte in table entry
        btfsc   PLUSW0,teLAST,0     ; Is this the end-of-module entry?
        bra     INIEXIT             ; Exit on last ID command
        bra     ENUMROM

INIT2
        movlw   cmdCONFIGURE
        cpfseq  CMD,0               ; Skip if CONFIGURE
        bra     ENUMCHK             ; See if no longer being configured
        ; Execute CONFIGURE command
        FLAGHI
        ; 7 instruction cycles during posedge
        LOADREG ADDR,APTR,ARANGE
        rlcf    ADDR+1,0            ; Addr bit 15 to carry
        rlcf    ADDR+2,0            ; Addr bits 19 downto 15
        movwf   ARANGE
        FLAGLO
DOMAP
        ; Mapping table entry precomputed during reset
        movlw   teADDR              ; Entry index of mapping address
        movff   PLUSW0,MAPVAL       ; Block number to temporary
        movlw   teID1               ; First ID nibble is ROM size
        movff   PLUSW0,ROMSIZ       ; Table entry ID first nibble
        movf    ARANGE,0            ; Table address is upper 5 bits of address
        movff   MAPVAL,PLUSW2       ; Entry is Block number!
        movlw   te16K               ; 16K ROM size
        cpfslt  ROMSIZ              ; Skip if ROM larger than 16K
        bra     INICHK
        movlw   0x20                ; Increment top 3 mapping bits
        addwf   MAPVAL                ; Point to next block
        movf    ARANGE,0            ; Table address is upper 5 bits of address
        incf    WREG                ; ROM is 32K or 64K
        movff   MAPVAL,PLUSW2         ; Entry is Block number!
        movlw   te32K               ; 32K ROM size
        cpfslt  ROMSIZ              ; Skip if ROM larger than 32K
        bra     INICHK
        movf    ARANGE,0            ; Table address is upper 5 bits of address
        movlw   0x20                ; Increment top 3 mapping bits
        addwf   MAPVAL                ; Point to next block
        movf    ARANGE,0            ; Table address is upper 5 bits of address
        addlw   0x02                ; ROM is 64K
        movff   MAPVAL,PLUSW2         ; Entry is Block number!
        movlw   0x20                ; Increment top 3 mapping bits
        addwf   MAPVAL                ; Point to next block
        movf    ARANGE,0            ; Table address is upper 5 bits of address
        addlw   0x03                ; ROM is 64K
        movff   MAPVAL,PLUSW2         ; Entry is Block number!
INICHK
        ; Check boundary condition: Last entry to enumerate
        movlw   teFLAG              ; Flag byte in table entry
        btfsc   PLUSW0,teLAST,0     ; Is this the end-of-module entry?
        bra     INIEXIT             ; Exit on last ID/Configure command

        movlw   ROMLEN              ; Bump pointer to next ROM entry
        addwf   FSR0L,1,0
        
        ; Check boundary condition: No last flag, end of table
        dcfsnz  CNTR                ; Skip if there are more table entries left
        bra     INIEXIT             ; Likely a missing Last flag not set
        ; Check boundary condition: No last flag, next entry is hard ROM
        movlw   teFLAG
        btfsc   PLUSW0,teHARD,0     ; Skip if hard ROM bit is clear
        bra     INIEXIT             ; Likely a missing Last flag not set
        ; Check boundary condition: Hidden ROM entry
        movlw   teBANK              ; Check to see if next entry is hidden ROM
        movff   PLUSW0,TEMP         ; Get block number
        movlw   0x00                ; Block zero is hidden ROM
        cpfsgt  TEMP,0              ; Skip if not hidden ROM
        bra     INIHDN              ; See if hidden ROM is not visible
        bra     ENUMCHK
INIHDN
        ; Check boundary condition: Hidden ROM is disabled
        btfsc   ROMNUM,cfHIDDEN,0   ; Should hidden ROM be configured?
        bra     ENUMCHK             ; Hidden ROM enabled, continue
        movlw   teFLAG
        btfsc   PLUSW0,teLAST,0     ; Skip if not Last Flag
        bra     INIEXIT             ; Disabled hidden ROM, go to next entry
        bra     INICHK

ENUMCHK
        btfsc   SIGPORT,Din,0       ; Exit when Din deasserted because we
        bra     ENUMROM             ;  messed up with missing Last flag
INIEXIT
        ; See if there's a hard ROM in last two table entries
        lfsr    FSR1,ROMDAT+((NROMS-2)*ROMLEN)
        movlw   teFLAG              ; See if hard ROM flag set
        btfss   PLUSW1,teHARD,0     ; Skip if flag set
        bra     EXITINI             ; Not set, finish up
        movlw   0xc0                ; Mapping bits for bank 6
        movwf   TEMP
        movlw   teADDR
        movf    PLUSW1,0,0          ; Mapping address to WREG
        movff   TEMP,PLUSW2
        movlw   ROMLEN              ; Bump pointer to next ROM entry
        addwf   FSR1L,1,0
        movlw   0xe0                ; Mapping bits for bank 7
        movwf   TEMP
        movlw   teADDR
        movf    PLUSW1,0,0          ; Mapping address to WREG
        movff   TEMP,PLUSW2
EXITINI
        banksel PIR0
        bcf     PIR0,INT0IF,1       ; Clear CDn flag
        bcf     PIR0,INT1IF,1       ; Clear Din flag
        banksel CMD
        setf    RDY                 ; Device has been configured
        bsf     INTCON,GIEH,0       ; High Priority Interrupt Enable
        bsf     INTCON,GIEL,0       ; Low Priority Interrupt Enable
        bra     IDLE
        



;*******************************************************************************
; IDLE TASK
; Synopsis
;  When the ROM emulator is not executing a bus command, it sits in the Idle
;  task. The Idle task can save power by switching to the Sleep mode when no
;  bus activity has occurred for a specified timeout period. It can also check
;  the serial port and invoke the Monitor task when activity is detected.
;  The serial port configuration should enable wake on sleep if it is used
;  when the PIC has entered sleep mode. See the BAUD1CON register description.
; 
;*******************************************************************************
NODOFF
        ;FLAGLO
        ; Set up power saving configuration
        banksel CMD
        ;FLAGHI
        clrf    PORTB               ; Set outputs low to save power
;*******************************************************************************
; EXPERIMENTAL!
; This code is used to assert & deassert the Halt signal to the Saturn CPU to
; allow the PIC enough time to recover from sleep and continue processing.
; Its purpose is to support a takeover ROM.
;*******************************************************************************
;        bsf     SIGLAT,Halt71,0     ; Set HALT signal high
;        bcf     SIGTRIS,Halt71,0    ; Enable HALT signal output driver
;*******************************************************************************
        bcf     INTCON,GIEH,0       ; Interrupt Disable, don't invoke ISR
        banksel CPUDOZE
        bcf     CPUDOZE,IDLEN,1     ; Some suggest this must be before sleep
        sleep
        bra     INITDEV             ; Wait for initiaization on CDn or Din
IDLE
        ;banksel CPUDOZE
        ;movlw   0x67                ; Doze, Recover on Interrupt, 1:256
        ;movwf   CPUDOZE,1
        banksel CMD
        clrf    APTR                ; Timeout counter for inactivity
        clrf    APTR+1
        clrf    APTR+2
        clrf    CNTR
IDLELP
        IFDEF  XTRNBOOT
        ; Check for Break on serial port
        banksel PIR3
        btfss   PIR3,RC1IF          ; Receive Interrupt bit set?
        bra     NOBREAK             ; No
        btfss   RC1STA,FERR         ; Framing Error?
        bra     NOBREAK             ; No
        btfsc   PORTC,7             ; Receive line low?
        bra     NOBREAK             ; No
        reset                       ; Bounce into bootloader
NOBREAK
        ENDIF   ; end of #ifdef XTRNBOOT

        IFDEF   SERMON
        ; Check for serial port activity
        banksel PIR3
        btfsc   PIR3,RC1IF          ; Receive Interrupt bit set?
        goto    MONITOR             ; Handle incoming serial data
        banksel CMD
        ENDIF

        INCREG  APTR                ; Incrementing every 1/(64MHz/256)
        btfsc   STATUS,C            ; Skip if no carry
        incf    CNTR
        btfsc   CNTR,4              ; About 2.5 minutes
        bra     NODOFF
        bra     IDLELP

;*******************************************************************************
; COMMAND DISPATCH TASK
; Synopsis
;  The high priority interrupt service routine transfers control directly here
;  when CDn goes low. That occurs roughly 7 instruction cycles before a command
;  is valid and 16 instruction cycles before the rising edge of STRn when the
;  command bus is sampled.
; 
; Detail
;  The command jump table needs to reside contiguously in a single 256 byte
;  page so that an offset can be added to PCL without generating a carry to
;  PCH. 
;  The jump table consists of a series of branch instructions. Should the code
;  grow larger some routines may lay beyond the reach of the short branch
;  range. Changing branches to goto instructions would require doubling the
;  size of the computed offset. The necessary instruction has been left in the
;  code and commented out.
;  
;*******************************************************************************
CMDREAD
        banksel CMD
        ;FLAGHI
        BUSRD
        ;FLAGLO
        bsf     INTCON,GIE,0        ; Global Interrupt Enable
        ;btfss  RDY,0               ; Has anything been enumerated?
        ;bra    IDLE                ; RDY=0, no ROM
    
DISPATCH
        ; 8 instruction cycles following ISR
        ; Computed branch, a bra is 1 word long
        movwf   CMD,1               ; Save command
        movlw   high(TABLE)
        movwf   PCLATH,0            ; Set PCH to 0x03--
        rlncf   CMD,0,0             ; CMD * 2 to WREG for bra offset
        ;rlncf   WREG,0,0            ; CMD * 4 for a goto offset
        movwf   PCL,0

;        ORG 0x1500
        ORG 0xd00
TABLE
        ; jump table for 16KB ROM images
        bra    DEADHEAD    ;CMDWAIT
        bra    DEADHEAD    ;ID
        bra    PCREAD
        bra    DPREAD
        bra    PCWRITE
        bra    DPWRITE
        bra    LOADPC
        bra    LOADDP
        bra    DEADHEAD    ;CONFIGURE
        bra    UNCONFIG
        bra    POLL
        bra    DEADHEAD    ;CMDWAIT
        bra    BUSCC
        bra    DEADHEAD    ;CMDWAIT
        bra    SHUTDWN
        bra    RESETX
;*******************************************************************************
; Jump table for external progams loaded into "chip" 0. The functions will
; Be accessable regardless to code version changes.
        goto   IDLE
        goto   NODOFF
        goto   DISPATCH
        goto   INITDEV
        goto   MONITOR
        call   CHAROUT
        call   GETSLOT
        call   GETBLK
        call   ASC2HEX
        call   NVMLINE
        call   ERASESEC
        call   READSEC
        call   WRITEHOLD
        call   WRITESEC
    
;*******************************************************************************
; IGNORE COMMAND
; Modules ignore some commands, so just return to the Idle loop after
; CDn rises.
;*******************************************************************************
DEADHEAD
        ;POSEDGE CDn
        bra     IDLE
    
;*******************************************************************************
; RESPOND TO ID COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Should only work if Daisy-in is high.
; 
; This routine is not used, but could be used if a system takeover ROM is
; implemented AND other ROM images are enumerated. The Initialize Device task
; would not be used.
;*******************************************************************************
ID
        btfss   SIGPORT,Din,0       ; Only respond when Daisy-In high
        bra     IDLE
        btfsc   IDSENT,0,0          ; Skip if all ID haven't been sent
        bra     IDLE                ; All done
        NEGEDGE STRn                ; 2~4 + 5
        movlw   0x00
        BUSWR   PLUSW0
        DATAOUT
        ;FLAGHI
        POSEDGE STRn                ; 2~4 + 4 instruction cycles
        DATAIN
        ;
        movlw   0x01
        BUSWR   PLUSW0
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn                ; 2~4 + 4 instruction cycles
        DATAIN
        ;
        movlw   0x02
        BUSWR   PLUSW0
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn                ; 2~4 + 4 instruction cycles
        DATAIN
        ;
        movlw   0x03
        BUSWR   PLUSW0
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn                ; 2~4 + 4 instruction cycles
        DATAIN
        ;
        movlw   0x04
        BUSWR   PLUSW0
        NEGEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAOUT
        POSEDGE STRn                ; 2~4 + 2 instruction cycles
        DATAIN
        ;FLAGLO
        movlw   0x04
        btfsc   PLUSW0,teEOM,0      ; Skip if end of module bit is clear
        setf    IDSENT              ; Set flag so as not to repeat ID
        movlw   ROMLEN              ; Bump pointer to next ROM entry
        addwf   FSR0L,1,0
        bra     IDLE
    

;*******************************************************************************
; RESPOND TO PC WRITE COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Always increment the PC register, even though no data is written.
; The TBLPTR should also be incremented as well when multiple ROMs are added.
;*******************************************************************************
PCWRITE
        NEGEDGE STRn                ; 2~4 + 11 instruction cycles (!)
        btfss   MIOVLD,0            ; Skip if MMIO selected
        bra     IDLE
        lfsr    FSR1,ROMNUM         ; MMIO buffer pointer
        movf    PCREG,0,0           ; MMIO address offset
        andlw   MMIOMASK            ; 16 registers in MMIO
        addwf   FSR1L,1,0           ; Bump MMIO buffer pointer
        ;FLAGHI
        POSEDGE STRn                ; 2~4 + 3 (+ 9) instruction cycles
        BUSRD
        ;movwf   ROMNUM              ; Just update ROM # for now
        movwf   POSTINC1,0          ; Save
        ;FLAGLO
        bra     IDLE                ; Ignore remaining nibbles
    

;*******************************************************************************
; RESPOND TO DP WRITE COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Always increment the DP register, even though no data is written.
; The TBLPTR should also be incremented as well when multiple ROMs are added.
;*******************************************************************************
DPWRITE
        NEGEDGE STRn                ; 2~4 + 11 instruction cycles (!)
        btfss   MIOVLD,0            ; Skip if MMIO not selected
        bra     IDLE
        lfsr    FSR1,ROMNUM         ; MMIO buffer pointer
        movf    DPREG,0,0           ; MMIO address offset
        andlw   MMIOMASK            ; 16 registers in MMIO
        addwf   FSR1L,1,0           ; Bump MMIO buffer pointer
        ;FLAGHI
        POSEDGE STRn                ; 2~4 + 3 (+ 9) instruction cycles
        BUSRD
        ;movwf   ROMNUM              ; Just update ROM # for now
        movwf   POSTINC1,0          ; Save
        ;FLAGLO
        bra     IDLE                ; Ignore remaining nibbles

;*******************************************************************************
; RESPOND TO LOAD PC COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Load the TBLPTR register as well to point to flash memory image.
;*******************************************************************************
LOADPC          ; Specifically for 16KB ROM images
        ;FLAGHI
        LOADREG PCREG,PPTR,PRANGE
        ;FLAGLO
        ;bra     PCREAD             ; Just fall through
    
;*******************************************************************************
; RESPOND TO PC READ COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Always increment the PC register. Output data only when the PC is in the
; assigned ROM address range, which is ADDR to ADDR+ROMSIZE-1.
; For multiple ROM chips, TBLPTR will also need to always be incremented.
;*******************************************************************************
PCREAD
        ; First read cycle is a dummy cycle
        NEGEDGE STRn                ; 2~4 + 15 instruction cycles (!)
        movlw   0x00
        cpfsgt  PRANGE              ; Don't output if ROM not selected
        bra     IDLE
        FLAGHI
        PTRLOAD PPTR
        tblrd   *
        btfsc   PCREG,0             ; Even or odd nibble (skip if even)
        swapf   TABLAT,1,0          ; Odd nibble is high nibble of PFM byte
        movff   TABLAT,CMDLAT       ; Transfer FPM byte to WREG
        FLAGLO
        POSEDGE STRn                ; Make sure!
DMYPCRD
        ; Merge two half cycles because of timing (2~4 + 17/18 IC)
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 7/8 instruction cycles
        DATAOUT
        ; Output nibble at start of read cycle
        incf    PCREG,1
        btfss   PCREG,0             ; Skip if PCREG incremented to odd
        tblrd   +*
        btfsc   PCREG,0             ; Even or odd nibble (skip if even)
        swapf   TABLAT,1,0          ; Odd nibble is high nibble of PFM byte
        ; Never merge a NEGEDGE! STRn can get stretched
        ;POSEDGE STRn               ; 2~4 + 12 instruction cycles (!)
        PTRSAVE PPTR                ; Save latest value
        DATAIN
        movff   TABLAT,CMDLAT       ; Transfer FPM byte to WREG
        bra DMYPCRD
    

;*******************************************************************************
; RESPOND TO LOAD DP COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Load the TBLPTR register as well to point to flash memory image.
;*******************************************************************************
LOADDP          ; Specifically for 16KB ROM images
        ;FLAGHI
        LOADREG DPREG,DPTR,DRANGE
        ; 11 instruction cycles following last nibble
        ;FLAGLO
        ;bra     DPREAD             ; Just fall through
    
;*******************************************************************************
; RESPOND TO DP READ COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Always increment the DP register. Output data only when the DP is in the
; assigned ROM address range, which is ADDR to ADDR+ROMSIZE-1.
;*******************************************************************************
DPREAD
        NEGEDGE STRn                ; 2~4 + 15 instruction cycles (!)
        movlw   0x00
        cpfsgt  DRANGE              ; Don't output if ROM not selected
        bra     IDLE
        FLAGHI
        PTRLOAD DPTR
        tblrd   *
        btfsc   DPREG,0             ; Even or odd nibble (skip if even)
        swapf   TABLAT,1,0          ; Odd nibble is high nibble of PFM byte
        movff   TABLAT,CMDLAT       ; Transfer FPM byte to WREG
        FLAGLO
        POSEDGE STRn                ; Make sure!
DMYDPRD
        ; Merge two half cycles because of timing (2~4 + 17/18 IC)
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 7/8 instruction cycles
        DATAOUT
        ; Output nibble at start of read cycle
        incf    DPREG,1
        btfss   DPREG,0             ; Skip if incremented DPREG to odd
        tblrd   +*
        btfsc   DPREG,0             ; Even or odd nibble (skip if even)
        swapf   TABLAT,1,0          ; Odd nibble is high nibble of PFM byte
        ; Never merge a NEGEDGE! STRn can get stretched
        ;POSEDGE STRn               ; 2~4 + 12 instruction cycles (!)
        PTRSAVE DPTR                ; Save latest value
        DATAIN
        movff   TABLAT,CMDLAT       ; Transfer FPM byte to WREG
        bra     DMYDPRD
    

;*******************************************************************************
; RESPOND TO CONFIGURE COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Only respond to this command when Daisy-in is high.
; 
; The code is not currently used. It would only work as currently written
; if the ROM table is organized as a series of 16K chips. This code is placed
; here for now should a takeover ROM be implemented and other ROM images
; would be enumerated.
; 
; This code currently would overflow into the next command, a PC Read. It
; likely would need to disable interrupts then branch into the Read routine.
;*******************************************************************************
CONFIGURE
        btfss   SIGPORT,Din,0       ; Only when Daisy-In asserted
        bra     IDLE
        ;FLAGHI
        LOADREG ADDR,APTR,ARANGE
        ; 10 instruction cycles following last nibble
        movlw   teADDR              ; Get prebuilt mapping bits
        movff   PLUSW1,MAPVAL       ; Block number to temporary
        movf    ARANGE,0            ; Table address is upper 5 bits of address
        movff   MAPVAL,PLUSW2       ; Entry is Block number!
        movlw   ROMLEN              ; Increment to next ROM entry
        addwf   FSR1L,1,0
        ;FLAGLO
        bra     IDLE
    

;*******************************************************************************
; RESPOND TO UNCONFIGURE COMMAND
; Command executes immediately on entry. STRn has already gone low and is
; likely high by the time DISPATCH transfters execution.
; 
;*******************************************************************************
; Only a device selected by its Data Pointer is supposed to respond to the
; UNCONFIGURE command. This is only done for RAM, not ROM. Only the selected
; RAM should be put in the unassigned state. Unconfiguring RAM would precede
; a configuration pass with Daisy-In.
;*******************************************************************************
; 
; With Daisy-In high generating an interrupt that vectors control to the
; Initialize Device task, the high priority interrupt should be disabled and
; control transferred to the Idle task, or to the Initialize Device task if
; Daisy-In is already high.
;*******************************************************************************
UNCONFIG
        ; 3/7 instruction cycles following command dispatch
        FLAGHI
        movlw   0x00
        cpfseq  DRANGE              ; Don't output if ROM not selected
        bra     IDLE
        clrf    RDY                 ; Device has been unconfigured
        FLAGLO
        bra     IDLE                ; Should wait for Din rising edge
    

;*******************************************************************************
; RESPOND TO POLL COMMAND
;*******************************************************************************
POLL
        bra     IDLE
    

;*******************************************************************************
; RESPOND TO BUSCC COMMAND
;*******************************************************************************
BUSCC
        bra     IDLE
    

;*******************************************************************************
; RESPOND TO SHUTDOWN COMMAND
; Command executes immediately on entry. STRn has already gone low and is
; likely high by the time DISPATCH transfters execution.
; A SHUTDOWN command is issued before the HP-71B CPU goes into sleep mode. The
; MultiModule needs to do the same thing.
;*******************************************************************************
SHUTDWN
        ;FLAGHI
        ;NEGEDGE STRn
        ;FLAGLO
        bra     IDLE
    

;*******************************************************************************
; RESPOND TO RESET COMMAND
; Command executes immediately on entry. STRn has already gone low and is
; likely high by the time DISPATCH transfters execution.
; A RESET command puts the module back into the wait for Daisy-In configuration
; state.
;*******************************************************************************
RESETX
        ; 5 instruction cycles following command dispatch
        FLAGHI
        ;clrf    RDY
        ;clrf    IDSENT              ; Haven't responded to ID command
        ;lfsr    FSR0,ROMDAT         ; Point to first ROM entry
        ;lfsr    FSR1,ROMDAT         ; Point to first ROM entry bank number
        call    INITVAR             ; Initialize variables and pointers
        call    INITTAB             ; Unmap all ROMs
        FLAGLO
        bra     INITDEV


;*******************************************************************************
; INITIALIZE HARDWARE
; Registers and register values taken from MCC generated C files
; During initialization:
;    All SPRs access through BANKSEL register
; During operation:
;   All registers are addressed through the Access Bank, where SRAM page zero
;   is mapped to 0x00 - 0x5f and SFR page 15 is mapped to 0x60 - 0xff.
;*******************************************************************************
INITMOD
; Taken from mcc_generated_files/mcc.c
        banksel PMD0
        movlw   0xff                ; Disable all peripheral modules
        movwf   PMD0,1
        movwf   PMD1,1
        movwf   PMD2,1
        movwf   PMD3,1
        movwf   PMD4,1
        movwf   PMD5,1
        bcf     PMD0,SYSCMD         ; Enable System Clock Network
        bcf     PMD0,NVMMD          ; Enable NVM Module
        bcf     PMD0,IOCMD          ; Enable Interrupt on Change
; Taken from mcc_generated_files/pin_manager.c
        banksel LATA
        clrf    LATA,1              ; Clear all port output latches
        clrf    LATB,1
        clrf    LATC,1
        movlw   0xff                ; Disable all outputs
        movwf   TRISA,1
        movwf   TRISB,1
        movwf   TRISC,1
        banksel ANSELA
        movlw   0xE0                ; Disable unused digital inputs
        movwf   ANSELA,1
        movlw   0xF0
        movwf   ANSELB,1
        movlw   0x00
        movwf   ANSELC,1
        clrf    WPUA,1              ; Disable output pullups
        clrf    WPUB,1
        clrf    WPUC,1
        clrf    WPUE,1
        clrf    ODCONA,1            ; Outputs source and sink
        clrf    ODCONB,1
        clrf    ODCONC,1
        movlw   0xFF                ; Pin slew rate limited (less noise)
        movwf   SLRCONA,1
        clrf    SLRCONB,1           ; Fast slew rate (might help)
        ;movwf   SLRCONB,1
        movwf   SLRCONC,1
        movlw   0xFF                ; Input level select, ST (CMOS) input
        ;movlw   0x00               ; Input level select, TTL input
        movwf   INLVLA,1
        movwf   INLVLB,1
        movwf   INLVLC,1
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

; From data sheet, 2.6 Unused I/Os
        ; Set as output, set low. All LATs have already been cleared
        banksel TRISA
        movlw   0x1f                ; Port A, bits 5-7 output
        andwf   TRISA,1             ; Clear bits 5-7
        movlw   0xcf                ; Port B, bits 4-5 output
        andwf   TRISB,1             ; Clear bits 4-5
        ; Port C eventually connected to SPI SRAM
        movlw   0x00                ; Port C, bits 0-7 output
        andwf   TRISC,1             ; Port C, all output

;//<editor-fold defaultstate="open" desc="Serial Monitor">
        IFDEF   SERMON
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
        else
        movlw   0x0f                ; Port B, bits 4-7 output
        andwf   TRISB,1,0           ; Clear bits 4-7
        movff   RC1REG,WREG         ; Clear interrupt bit
        ENDIF   ; end of #ifdef SERMON
;//</editor-fold>

        ; Interrupt configuration (CDn fall, Din rise)
; From interrupt_manager.c, INTERRUPT_Initialize()
        banksel INTCON
        bsf     INTCON,IPEN,1       ; Enable Interrupt Priority Vectors
        banksel IPR0
        bsf     IPR0,INT0IP,1       ; INT0I - high priority
        bcf     IPR0,INT1IP,1       ; INT1I - low priority
; From pinmanager.c, PIN_MANAGER_Initialize()
        banksel IOCAF
        ; CDn interrupt on falling edge
        bcf     IOCAF,IOCAF4,1      ; Interrupt on Change flag
        bsf     IOCAN,IOCAN4,1      ; Interrupt on negative edge
        bcf     IOCAP,IOCAP4,1      ; Interrupt on positive edge
        ; Din interrupt on rising edge
        bcf     IOCAF,IOCAF2,1      ; Interrupt on Change flag
        bcf     IOCAN,IOCAN2,1      ; Interrupt on negative edge
        bsf     IOCAP,IOCAP2,1      ; Interrupt on positive edge

        banksel INT0PPS
        movlw   0x04                ; RA4->EXT_INT:INT0
        movwf   INT0PPS,1
        movlw   0x02                ; RA2->EXT_INT:INT1
        movwf   INT1PPS,1



; From ext_int.c, EXT_INT_Initialize()
        banksel PIR0
        bcf     PIR0,INT0IF,1       ; Clear interrupt flag
        bcf     PIR0,INT0IF,1       ; Clear interrupt flag

        banksel INTCON
        bcf     INTCON,INT0EDG,1    ; Falling edge CDn
        bsf     INTCON,INT1EDG,1    ; Rising edge Din

        banksel PIE0
        bsf     PIE0,INT0IE,1       ; External interrupts enable
        bsf     PIE0,INT1IE,1       ; External interrupts enable

#ifdef __18F27K40
        ; Seems to be needed, at least at initialization
        bcf     NVMCON1,NVMREG0     ; point to Program Flash Memory
        bsf     NVMCON1,NVMREG1     ; access Program Flash Memory
#endif

        return
    

;*******************************************************************************
; HARD RESET
; Initialize program variables
;*******************************************************************************
HARDRST
        banksel CMD                 ; Default for all BSR accesses
        movlw   0x0                 ; No ROM configuration is active
        movwf   ROMNUM
        ; Initialize static variables
        movlw   ROMLEN              ; Length of ROM configuration string
        mullw   NROMS+1             ; Extra ROM entry for MMIO address
        movff   PRODL,CNTR          ; # of bytes to transfer
        movlw   high(ROM1)          ; ROM string address
        movwf   TBLPTRH,0
        movlw   low(ROM1)
        movwf   TBLPTRL,0
        lfsr    FSR0,ROMDAT         ; Transfer target address
        ;;; 8*N cycles ;;;
HALOOP
        tblrd   *+
        movf    TABLAT,0,0          ; Transfer FPM byte to WREG
        movwf   POSTINC0,0          ; Store to RAM
        decfsz  CNTR,1,0            ; Done when counter is zero
        bra     HALOOP

        ; Initialize ROM table entry values in RAM
        lfsr    FSR0,ROMDAT         ; Transfer target address
        movlw   NROMS               ; Number of ROM table entries
        movwf   CNTR
HALOOP2
        movlw   teFLAG
        btfsc   PLUSW0,teHARD,0     ; See if we've reached the hard ROM entries
        bra     HAROMS              ; Finish up the two hard rom entries
        movlw   teBANK
        movff   PLUSW0,TEMP         ; Read PFM block number to TEMP
        rrncf   TEMP                ; Rotate right 3 times to form ADDR byte
        rrncf   TEMP
        rrncf   TEMP
        movlw   0x00
        cpfseq  TEMP                ; Addressing PFM block 0?
        bra     HA1_7
        movlw   0x10                ; ADDR byte for 8K ROM in block 0
        movwf   TEMP
HA1_7
        movlw   teADDR
        movff   TEMP,PLUSW0         ; Update ADDR byte
        movlw   ROMLEN              ; Length of a ROM table entry
        addwf   FSR0L,1,0           ; Increment to next table entry
        decfsz  CNTR,1,0            ; Done when counter is zero
        bra     HALOOP2
HAROMS
        movlw   teADDR
        addwf   FSR0L,1,0           ; Bump pointer to ADDR byte of entry
        movlw   0x1c                ; ADDR value for first hard ROM
        movwf   INDF0
        movlw   ROMLEN              ; Length of a ROM table entry
        addwf   FSR0L,1,0           ; Increment to next table entry
        movlw   0x1d                ; ADDR value for second hard ROM
        movwf   INDF0
        return
    

;*******************************************************************************
; SOFT RESET
; Initialize program variables
;*******************************************************************************

INITVAR
        banksel CMD                 ; Default for all BSR accesses
        clrf    RDY
        clrf    MIOVLD
        clrf    IDSENT              ; Haven't responded to ID command
        lfsr    FSR0,ROMDAT         ; Point to first ROM entry
        lfsr    FSR1,ROMDAT         ; Point to first ROM entry bank number
        return


;*******************************************************************************
; SOFT RESET 2
; Initialize address mapping table
;*******************************************************************************
INITTAB
        ; Set up & initialize address mapping table
        lfsr    FSR2,MAPTBL         ; Base address of mapping table
        movlw   0x20                ; 32 table entries
MPTBLP
        clrf    PLUSW2,0            ; Clear table entry
        decfsz  WREG,0
        bra     MPTBLP
        clrf    PLUSW2,0            ; Clear last table entry
        return

;*******************************************************************************
; SERIAL MONITOR
; The serial monitor provides a way to easily modify a ROM configuration and
; upload ROM images.
;*******************************************************************************
        ifdef   SERMON
#include monitor.inc
        endif

        data "(c) Mark A. Fleming 2021"
        END
