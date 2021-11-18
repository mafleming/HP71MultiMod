    LIST
;*******************************************************************************
;                                                                              *
;    Filename:      rommain.s                                                *
;    Date:          November 10, 2021                                              *
;    File Version:  1.0                                                        *
;    Author:        Mark A. Fleming                                            *
;    Company:                                                                  *
;    Description:   Emulate HP-71B ROM memory                                  *
;                                                                              *
;*******************************************************************************
;    Notes:                                                                    *
;      5/12/2021, port the existing MultiMod source code to the MPLAB X IDE    *
;      version 5.50 which uses a different assembler from the old MPASM.       *
;      Changes should mostly be in assembler directives and CONFIG settings.   *
;                                                                              *
;*******************************************************************************
;                                                                              *
;    Revision History:                                                         *
;    1.0  5-May-2021       Initiation for MPASM                                *
;    2.0  3-October-2022   Port to XC8 Assembler                               *
;    2.1  10-November-2022 Port to XC8 Assembler for the PIC18F27Q10           *
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
;  0 0800 - 0 08FF   Program Constants
;  0 0900 - 0 097F   High Priority Interrupt Service Routine
;  0 0980 - 0 09FF   Low Priority Interrupt Service Routine
;  0 0A00 - 0 1FFF   Application Code
;  0 2000 - 0 03FF   ROM Block 0
;  0 4000 - 0 7FFF   ROM Block 1
;  0 8000 - 0 BFFF   ROM Block 2
;  0 C000 - 0 FFFF   ROM Block 3
;  1 0000 - 1 3FFF   ROM Block 4
;  1 4000 - 1 7FFF   ROM Block 5
;  1 8000 - 1 BFFF   ROM Block 6
;  1 C000 - 1 FFFF   ROM Block 7
;  
; General Purpose Register Usage
;  0 00 - 0 2F       Program Variables
;  0 30 - 0 7F       ROM Configuration Table
;  0 E0 - 0 FF       71B Address Mapping Table
;  1 00 - 1 FF       Serial Monitor Character Buffer
;  2 00 - 2 FF       Flash Write Sector Buffer
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
;  into Program Flash Memory and the three pointers into data SRAM; FSR0, FSR1,
;  and FSR2. All four are used during initialization. During ROM Emulator
;  operation, the pointers in use are
;  
;  TBLPTR  Used to address PFM byte holding the next nibble to return by a
;          PCREAD or DPREAD command. The address is computed by the LOADPC or
;          LOADDP command and s saved after every use to locations PPTR or DPTR.
;  FSR0    Used as a scratch register for miscellaneous SRAM accesses.
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
;  An 8K ROM image is currently supported in the upper half of PFM Block 0,
;  address range 0x2000~0x3FFF. This image is enumerated as a 16KB ROM during
;  bus configuration.
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
;  A desirable enhancement of this software would be to make these true tasks
;  by making the CDn-driven high priority interrupt a true multitasking kernel.
;  There is a good deal of dead time when the 71B is addressing other devices
;  on the bus. Thus software must respond to every command but often control is
;  returned to the Idle task.
;  
; Command Processing
;  A command cycle begins when the CDn signal falls, then the STRn strobe clock
;  falls and then rises, marking a write cycle for the command. The falling
;  edge of CDn generates an interrupt that directs processor control to a
;  command dispatch routine. The interrupt was necessary because a command cycle
;  can begin in the midst of a series of Read or Write cycles. Timing
;  constraints proved too tight to simply check the state of the CDn signal
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
;  sampled too early before STRn rise.
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
;  for STRn rise. The second half-cycle of one IC can't be "merged" with the
;  first half-cycle of the next IC because the second half-cycle can on occasion
;  be stretched, even in the middle of a command or multi-read/write cycle.
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
;  command and store a 1 or 3 hex digit to address 2C000h. Turn the 71B off
;  then on again to make the ROM images available. If a value of zero is
;  written and power is cycled then all ROM images will be unavailable.
;  
;*******************************************************************************    


    LIST
    TITLE "HP71B ROM Emulator"

;*******************************************************************************
; Conditional Compilation Configuration Settings
; 
; If using an external bootloader usch as the one in AN851 or AN1310, define
; both XTRNBOOT and SERMON.
; If an internal serial monitor is part of the build, define SERMON.
; 
;*******************************************************************************    
PROCESSOR 18F27Q10

    NOLIST
#include <xc.inc>
    LIST


#include "config.inc"
#include "macros.inc"

;*******************************************************************************
; System Constants
;*******************************************************************************    
cmdNOP		EQU 0x0
cmdID		EQU 0x1
cmdPCREAD	EQU 0x2
cmdDPREAD	EQU 0x3
cmdPCWRITE	EQU 0x4
cmdDPWRITE	EQU 0x5
cmdLOADPC	EQU 0x6
cmdLOADDP	EQU 0x7
cmdCONFIGURE	EQU 0x8
cmdUNCONFIGURE	EQU 0x9
cmdPOLL		EQU 0xA
cmdRESERVED1	EQU 0xB
cmdBUSCC	EQU 0xC
cmdRESERVED2	EQU 0xD
cmdSHUTDOWN	EQU 0xE
cmdRESET	EQU 0xF

    ; Constants associated with ROM configuration table
teID1		EQU 0x00
teID2		EQU 0x01
teID3		EQU 0x02
teID4		EQU 0x03
teID5		EQU 0x04
teFLAG		EQU 0x05
teADDR		EQU 0x06
teBANK		EQU 0x07
te16K		EQU 0x0a
te32K		EQU 0x09
te64K		EQU 0x08
teEOM		EQU 0x03
teLAST		EQU 0x00
teHARD		EQU 0x01

    ; Constants associated with ROM configuration nibble ROMNUM
cfMAIN		EQU 0
cfHIDDEN	EQU 1

    ; 7 ROMs (plus add one for MMIO address)
NROMS		EQU 0x7
    ;; ROMLEN MUST BE EVEN!
ROMLEN		EQU 0x8
    ; The table offset to first of two Hard ROM slots
HRDSLOT		EQU 0x5
    ; The mask for the MMIO address (size in nibbles of IO block)
MMIOMASK	EQU 0x0f

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
PSECT   udata_acs
PUBLIC	CMD, RDY, ARANGE, DRANGE, PRANGE, MIOVLD, MIOADR, ROMNUM, CMDBUF
PUBLIC  ROMDAT, MMIO, MAPTBL
CMD:      DS      1                   ; Command register (nibble)
RDY:      DS      1                   ; Module ready flag
ADDR:     DS      3                   ; Configuration address (20 bits, 3 bytes)
PCREG:    DS      3                   ; PC register (20 bits, 3 bytes)
DPREG:    DS      3                   ; DP register (20 bits, 3 bytes)
ROMBANK:  DS      1                   ; Which of 8 PFM banks is active ROM
ROMSIZ:   DS      1                   ; Temporary used in initialization
MAPVAL:   DS      1                   ; Temporary used in initialization
ARANGE:   DS      1                   ; Address range bits 19 downto 15
DRANGE:   DS      1                   ; DP register range bits 19 downto 15
PRANGE:   DS      1                   ; PC register range bits 19 downto 15
CNTR:     DS      1                   ; General use counter
APTR:     DS      3                   ; Not used except as scratch
DPTR:     DS      3                   ; TBLPTR for DP register
PPTR:     DS      3                   ; TBLPTR for PC register
IDSENT:   DS      1                   ; Flag that ID has been sent, ignore ID cmd
TEMP:     DS      1                   ; Temporary variable
MIOVLD:   DS      1                   ; Address is in MMIO address range
MIOADR:   DS      1                   ; MMIO register to read/write
ADIGIT:   DS      1                   ; Temporary location for a digit (ASCII 0-8)
ROMNUM:   DS      1                   ; ROM Configuration nibble @ 2C000h
CMDBUF:   DS      1                   ; MMIO (16 bytes)/Command Buffer (6 bytes)

ROMDAT    EQU     0x30                ; ROM configuration initialized on start
        ; 5 nibble address of Memory-mapped I/O device
;MMIO   EQU     ROMDAT+ROMLEN*NROMS !This was computed as 0x188!!!
MMIO   EQU     ROMDAT+(ROMLEN*NROMS)  ; No operator precedence

MAPTBL  EQU     0xe0                ; Top 32 registers of page 0

DATABUF EQU     0x0100              ; Use SRAM page 1 for serial buffer
SECTBUF EQU     0x0200              ; Use SRAM page 2 for sector buffer

;*******************************************************************************
; Reset Vector
;*******************************************************************************
;PSECT resetVec,class=CODE,abs
PSECT code,abs
	org	0
RESVEC:
        goto    START               ; go to beginning of program

;*******************************************************************************
; Interrupt Service Vectors
;*******************************************************************************
;PSECT isvhiVec,class=CODE,abs
	org	0x08
IV1:
        goto    ISVHI
    
;PSECT isvloVec,class=CODE,abs
	org	0x18
IV2:
        goto    ISVLO


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
PSECT romCfg,class=CODE,abs
        ORG 0x40
	global ROM1
ROM1:
#include "ROMconfig.inc"
        ORG 0xC0
        DB 'C', 'o', 'p', 'y', 'r', 'i', 'g', 'h'
	DB 't', ' ', '2', '0', '2', '1', ',', ' '
	DB 'M', 'a', 'r', 'k', ' ', 'A', '.', ' '
	DB 'F', 'l', 'e', 'm', 'i', 'n', 'g'
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
;        ORG     0x900
;PSECT code, abs
        ORG     0x100
	global	ISVHI
ISVHI:
        ; How about POP, BRA CMDCYCLE ?
        movlw   high(CMDREAD)       ;Vector control to command processing
        movwf   TOSH,c
        movlw   low(CMDREAD)
        movwf   TOSL,c
        banksel PIR0
        bcf     INT0IF              ; Clear interrupt flag
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
        ORG     0x180
	global	ISVLO
ISVLO:
        ; Din goes high
        movlw   high(INITDEV)       ;Vector control to device initialization
        movwf   TOSH,c
        movlw   low(INITDEV)
        movwf   TOSL,c
        banksel PIR0
        bcf     INT1IF              ; Clear interrupt flag
        retfie


;*******************************************************************************
; MAIN PROGRAM AREA
;*******************************************************************************
;PSECT   ORG     0x1200
;        ORG     0x9a0
        ORG     0x200
	global	START
START:
        ; Hardware initialization here from power-on reset
        call    INITMOD
        call    HARDRST
        DATAIN                      ; Should always default to DATAIN
        ;; Debug
#ifdef   DBGFLAG
        bcf     DBGTRIS,DBGPIN,c    ; Set RA6 as output
        bcf     DBGPORT,DBGPIN,c    ; Clear flag
        bsf     DBGANSL,DBGPIN,c    ; Digital read returns '0'
#endif

;*******************************************************************************
; INITIALIZE DEVICE TASK
; Synopsis
;  Control begins here on the rising edge of the Daisy-In triggered
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
INITDEV:
        banksel CMD
        bcf     GIEH                ; High Priority Interrupt Disable
        bcf     GIEL                ; Low Priority Interrupt Disable
        banksel PIR0
        bcf     INT0IF              ; Clear interrupt flag
        bcf     INT1IF              ; Clear interrupt flag
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
        movwf   CNTR,c              ; Limit number of table entries scanned
        lfsr    0,ROMDAT            ; Point to first ROM entry

        movlw   0x00
        cpfsgt  ROMNUM,c            ; Skip if ROMNUM > 0
        bra     INIEXIT             ; A zero in ROMNUM unplugs all ROMs
                                    ; Should be EXITINI
        btfss   SIGPORT,Din,c       ; Only enumerate when Daisy-In is high
        bra     $-2                 ; This could be a hang until 71B turned on
ENUMROM:
        NEGEDGE CDn
        NEGEDGE STRn
        ;NEGEDGE STRn               ; Command appears much later in older 71B
        POSEDGE STRn                ; Must sample as close as can to this edge
        ;FLAGHI
        BUSRD
        movwf   CMD,c               ; Save command
        ;FLAGLO
        ;POSEDGE CDn
        movlw   cmdID
        cpfseq  CMD,c               ; Skip if ID
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
        ; Exit on last CONFIG command, not last ID
;        movlw   teFLAG              ; Flag byte in table entry
;        btfsc   PLUSW0,teLAST,c     ; Is this the end-of-module entry?
;        bra     INIEXIT             ; Exit on last ID command
        bra     ENUMROM

INIT2:
        movlw   cmdCONFIGURE
        cpfseq  CMD,c               ; Skip if CONFIGURE
        bra     ENUMCHK             ; See if no longer being configured
        ; Execute CONFIGURE command
        FLAGHI
        ; 7 instruction cycles during posedge

	LOADREG ADDR,APTR,ARANGE

        rlcf    ADDR+1,w,c          ; Addr bit 15 to carry
        rlcf    ADDR+2,w,c          ; Addr bits 19 downto 15
        movwf   ARANGE,c
        FLAGLO
DOMAP:
        ; Mapping table entry precomputed during reset
        movlw   teADDR              ; Entry index of mapping address
        movff   PLUSW0,MAPVAL       ; Block number to temporary
        movlw   teID1               ; First ID nibble is ROM size
        movff   PLUSW0,ROMSIZ       ; Table entry ID first nibble
        movf    ARANGE,w,c          ; Table address is upper 5 bits of address
        movff   MAPVAL,PLUSW2       ; Entry is Block number!
        movlw   te16K               ; 16K ROM size
        cpfslt  ROMSIZ,c            ; Skip if ROM larger than 16K
        bra     INICHK
        movlw   0x20                ; Increment top 3 mapping bits
        addwf   MAPVAL,f,c          ; Point to next block
        movf    ARANGE,w,c          ; Table address is upper 5 bits of address
        incf    WREG,f,c            ; ROM is 32K or 64K
        movff   MAPVAL,PLUSW2         ; Entry is Block number!
        movlw   te32K               ; 32K ROM size
        cpfslt  ROMSIZ,c            ; Skip if ROM larger than 32K
        bra     INICHK
        movf    ARANGE,w,c          ; ???Table address is upper 5 bits of address
        movlw   0x20                ; Increment top 3 mapping bits
        addwf   MAPVAL,f,c          ; Point to next block
        movf    ARANGE,w,c          ; Table address is upper 5 bits of address
        addlw   0x02                ; ROM is 64K
        movff   MAPVAL,PLUSW2         ; Entry is Block number!
        movlw   0x20                ; Increment top 3 mapping bits
        addwf   MAPVAL,f,c          ; Point to next block
        movf    ARANGE,w,c          ; Table address is upper 5 bits of address
        addlw   0x03                ; ROM is 64K
        movff   MAPVAL,PLUSW2         ; Entry is Block number!
INICHK:
        ; Check boundary condition: Last entry to enumerate
        movlw   teFLAG              ; Flag byte in table entry
        btfsc   PLUSW0,teLAST,c     ; Is this the end-of-module entry?
        bra     INIEXIT             ; Exit on last ID/Configure command

        movlw   ROMLEN              ; Bump pointer to next ROM entry
        addwf   FSR0L,f,c
        
        ; Check boundary condition: No last flag, end of table
        dcfsnz  CNTR,c              ; Skip if there are more table entries left
        bra     INIEXIT             ; Likely a missing Last flag not set
        ; Check boundary condition: No last flag, next entry is hard ROM
        movlw   teFLAG
        btfsc   PLUSW0,teHARD,c     ; Skip if hard ROM bit is clear
        bra     INIEXIT             ; Likely a missing Last flag not set
        ; Check boundary condition: Hidden ROM entry
        movlw   teBANK              ; Check to see if next entry is hidden ROM
        movff   PLUSW0,TEMP         ; Get block number
        movlw   0x00                ; Block zero is hidden ROM
        cpfsgt  TEMP,c              ; Skip if not hidden ROM
        bra     INIHDN              ; See if hidden ROM is not visible
        bra     ENUMCHK
INIHDN:
        ; Check boundary condition: Hidden ROM is disabled
        btfsc   ROMNUM,cfHIDDEN,c   ; Should hidden ROM be configured?
        bra     ENUMCHK             ; Hidden ROM enabled, continue
        movlw   teFLAG
        btfsc   PLUSW0,teLAST,c     ; Skip if not Last Flag
        bra     INIEXIT             ; Disabled hidden ROM, go to next entry
        bra     INICHK

ENUMCHK:
        btfsc   SIGPORT,Din,c       ; Exit when Din deasserted because we
        bra     ENUMROM             ;  messed up with missing Last flag
INIEXIT:
        ; See if there's a hard ROM in last two table entries
        lfsr    1,ROMDAT+((NROMS-2)*ROMLEN)
        movlw   teFLAG              ; See if hard ROM flag set
        btfss   PLUSW1,teHARD,c     ; Skip if flag set
        bra     EXITINI             ; Not set, finish up
        movlw   0xc0                ; Mapping bits for bank 6
        movwf   TEMP,c
        movlw   teADDR
        movf    PLUSW1,w,c          ; Mapping address to WREG
        movff   TEMP,PLUSW2
        movlw   ROMLEN              ; Bump pointer to next ROM entry
        addwf   FSR1L,f,c
        movlw   0xe0                ; Mapping bits for bank 7
        movwf   TEMP,c
        movlw   teADDR
        movf    PLUSW1,w,c          ; Mapping address to WREG
        movff   TEMP,PLUSW2
EXITINI:
        banksel PIR0
        bcf     INT0IF              ; Clear CDn flag
        bcf     INT1IF              ; Clear Din flag
        banksel CMD
        setf    RDY,c               ; Device has been configured
        bsf     GIEH                ; High Priority Interrupt Enable
        bsf     GIEL                ; Low Priority Interrupt Enable
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
	global NODOFF, IDLE
NODOFF:
        ;FLAGLO
        ; Set up power saving configuration
        banksel CMD
        ;FLAGHI
        clrf    PORTB,c             ; Set outputs low to save power
;*******************************************************************************
; EXPERIMENTAL!
; This code is used to assert & deassert the Halt signal to the Saturn CPU to
; allow the PIC enough time to recover from sleep and continue processing.
; Its purpose is to support a takeover ROM.
;*******************************************************************************
;        bsf     SIGLAT,Halt71,0     ; Set HALT signal high
;        bcf     SIGTRIS,Halt71,0    ; Enable HALT signal output driver
;*******************************************************************************
        bcf     GIEH                ; Interrupt Disable, don't invoke ISR
        banksel CPUDOZE
        bcf     IDLEN               ; Some suggest this must be before sleep
        sleep
        bra     INITDEV             ; Wait for initiaization on CDn or Din
IDLE:
        ;banksel CPUDOZE
        ;movlw   0x67                ; Doze, Recover on Interrupt, 1:256
        ;movwf   CPUDOZE,1
        banksel CMD
        clrf    APTR,c              ; Timeout counter for inactivity
        clrf    APTR+1,c
        clrf    APTR+2,c
        clrf    CNTR,c
IDLELP:

        INCREG  APTR                ; Incrementing every 1/(64MHz/256)
        btfsc   STATUS,0,c          ; Skip if no carry
        incf    CNTR,f,c
        btfsc   CNTR,4,c            ; About 2.5 minutes
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
	global	CMDREAD, DISPATCH, TABLE
CMDREAD:
        banksel CMD
        ;FLAGHI
        BUSRD
        ;FLAGLO
        bsf     GIE                 ; Global Interrupt Enable
        ;btfss  RDY,0               ; Has anything been enumerated?
        ;bra    IDLE                ; RDY=0, no ROM
    
DISPATCH:
        ; 8 instruction cycles following ISR
        ; Computed branch, a bra is 1 word long
        movwf   CMD,c               ; Save command
        movlw   high(TABLE)
        movwf   PCLATH,c            ; Set PCH to 0x03--
        rlncf   CMD,w,c             ; CMD * 2 to WREG for bra offset
        ;rlncf   WREG,0,0            ; CMD * 4 for a goto offset
        movwf   PCL,c

;        ORG 0x1500
;        ORG 0xd00
;	ORG	0xc80
	ALIGN 0x100
	global	DEADHEAD, PCREAD, DPREAD, PCWRITE, DPWRITE, LOADPC, LOADDP
	global	UNCONFIG, POLL, BUSCC, SHUTDWN, RESETX
TABLE:
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
#ifdef SERMON
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
#endif

;*******************************************************************************
; IGNORE COMMAND
; Modules ignore some commands, so just return to the Idle loop after
; CDn rises.
;*******************************************************************************
DEADHEAD:
        ;POSEDGE CDn
        ;FLAGHI
        ;FLAGLO
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
#if 0>1
ID:
        btfss   SIGPORT,Din,c       ; Only respond when Daisy-In high
        bra     IDLE
        btfsc   IDSENT,w,c          ; Skip if all ID haven't been sent
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
        btfsc   PLUSW0,teEOM,c      ; Skip if end of module bit is clear
        setf    IDSENT,c            ; Set flag so as not to repeat ID
        movlw   ROMLEN              ; Bump pointer to next ROM entry
        addwf   FSR0L,f,c
        bra     IDLE
#endif    


;*******************************************************************************
; RESPOND TO PC WRITE COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Always increment the PC register, even though no data is written.
; The TBLPTR should also be incremented as well when multiple ROMs are added.
;*******************************************************************************
PCWRITE:
        NEGEDGE STRn                ; 2~4 + 11 instruction cycles (!)
        btfss   MIOVLD,0,c          ; Skip if MMIO selected
        bra     IDLE
        lfsr    1,ROMNUM            ; MMIO buffer pointer
        movf    PCREG,w,c           ; MMIO address offset
        andlw   MMIOMASK            ; 16 registers in MMIO
        addwf   FSR1L,f,c           ; Bump MMIO buffer pointer
        ;FLAGHI
        POSEDGE STRn                ; 2~4 + 3 (+ 9) instruction cycles
        BUSRD
        ;movwf   ROMNUM              ; Just update ROM # for now
        movwf   POSTINC1,c          ; Save
        ;FLAGLO
        bra     IDLE                ; Ignore remaining nibbles
    

;*******************************************************************************
; RESPOND TO DP WRITE COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Always increment the DP register, even though no data is written.
; The TBLPTR should also be incremented as well when multiple ROMs are added.
;*******************************************************************************
DPWRITE:
        ;FLAGHI
        NEGEDGE STRn                ; 2~4 + 11 instruction cycles (!)
        ;FLAGLO
        btfss   MIOVLD,0,c          ; Skip if MMIO not selected
        bra     IDLE
        lfsr    1,ROMNUM            ; MMIO buffer pointer
        movf    DPREG,w,c           ; MMIO address offset
        andlw   MMIOMASK            ; 16 registers in MMIO
        addwf   FSR1L,f,c           ; Bump MMIO buffer pointer
        FLAGHI
        POSEDGE STRn                ; 2~4 + 3 (+ 9) instruction cycles
        BUSRD
        ;movwf   ROMNUM              ; Just update ROM # for now
        movwf   POSTINC1,c          ; Save
        FLAGLO
        bra     IDLE                ; Ignore remaining nibbles

;*******************************************************************************
; RESPOND TO LOAD PC COMMAND
; This command begins by waiting for the start of a read/write cycle
; where STRn goes low. The Command Bus will be in the input state.
; Load the TBLPTR register as well to point to flash memory image.
;*******************************************************************************
LOADPC:          ; Specifically for 16KB ROM images
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
PCREAD:
        ; First read cycle is a dummy cycle
        NEGEDGE STRn                ; 2~4 + 15 instruction cycles (!)
        movlw   0x00
        cpfsgt  PRANGE,c            ; Don't output if ROM not selected
        bra     IDLE
        FLAGHI
        PTRLOAD PPTR
        tblrd   *
        btfsc   PCREG,0,c           ; Even or odd nibble (skip if even)
        swapf   TABLAT,f,c          ; Odd nibble is high nibble of PFM byte
        movff   TABLAT,CMDLAT       ; Transfer FPM byte to WREG
        FLAGLO
        POSEDGE STRn                ; Make sure!
DMYPCRD:
        ; Merge two half cycles because of timing (2~4 + 17/18 IC)
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 7/8 instruction cycles
        DATAOUT
        ; Output nibble at start of read cycle
        incf    PCREG,f,c
        btfss   PCREG,0,c           ; Skip if PCREG incremented to odd
        tblrd   +*
        btfsc   PCREG,0,c           ; Even or odd nibble (skip if even)
        swapf   TABLAT,f,c          ; Odd nibble is high nibble of PFM byte
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
LOADDP:         ; Specifically for 16KB ROM images
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
DPREAD:
        NEGEDGE STRn                ; 2~4 + 15 instruction cycles (!)
        movlw   0x00
        cpfsgt  DRANGE,c            ; Don't output if ROM not selected
        bra     IDLE
        FLAGHI
        PTRLOAD DPTR
        tblrd   *
        btfsc   DPREG,0,c           ; Even or odd nibble (skip if even)
        swapf   TABLAT,f,c          ; Odd nibble is high nibble of PFM byte
        movff   TABLAT,CMDLAT       ; Transfer FPM byte to WREG
        FLAGLO
        POSEDGE STRn                ; Make sure!
DMYDPRD:
        ; Merge two half cycles because of timing (2~4 + 17/18 IC)
        ;FASTOUT                    ; 4~7 + 2 instruction cycles
        NEGEDGE STRn                ; 2~4 + 7/8 instruction cycles
        DATAOUT
        ; Output nibble at start of read cycle
        incf    DPREG,f,c
        btfss   DPREG,0,c           ; Skip if incremented DPREG to odd
        tblrd   +*
        btfsc   DPREG,0,c           ; Even or odd nibble (skip if even)
        swapf   TABLAT,f,c          ; Odd nibble is high nibble of PFM byte
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
;*******************************************************************************
#if 0>1
CONFIGURE:
        btfss   SIGPORT,Din,c       ; Only when Daisy-In asserted
        bra     IDLE
        ;FLAGHI
        LOADREG ADDR,APTR,ARANGE
        ; 10 instruction cycles following last nibble
        movlw   teADDR              ; Get prebuilt mapping bits
        movff   PLUSW1,MAPVAL       ; Block number to temporary
        movf    ARANGE,c            ; Table address is upper 5 bits of address
        movff   MAPVAL,PLUSW2       ; Entry is Block number!
        movlw   ROMLEN              ; Increment to next ROM entry
        addwf   FSR1L,f,c
        ;FLAGLO
        bra     IDLE
#endif


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
UNCONFIG:
        ; 3/7 instruction cycles following command dispatch
        FLAGHI
        movlw   0x00
        cpfseq  DRANGE,c            ; Don't output if ROM not selected
        bra     IDLE
        clrf    RDY,c               ; Device has been unconfigured
        FLAGLO
        bra     IDLE                ; Should wait for Din rising edge
    

;*******************************************************************************
; RESPOND TO POLL COMMAND
;*******************************************************************************
POLL:
        bra     IDLE
    

;*******************************************************************************
; RESPOND TO BUSCC COMMAND
;*******************************************************************************
BUSCC:
        bra     IDLE
    

;*******************************************************************************
; RESPOND TO SHUTDOWN COMMAND
; Command executes immediately on entry. STRn has already gone low and is
; likely high by the time DISPATCH transfters execution.
; A SHUTDOWN command is issued before the HP-71B CPU goes into sleep mode. The
; MultiModule needs to do the same thing.
;*******************************************************************************
SHUTDWN:
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
RESETX:
        ; 5 instruction cycles following command dispatch
        ;FLAGHI
        ;FLAGLO
        goto    INITDEV


;*******************************************************************************
; INITIALIZE HARDWARE
; Registers and register values taken from MCC generated C files
; During initialization:
;    All SPRs access through BANKSEL register
; During operation:
;   All registers are addressed through the Access Bank, where SRAM page zero
;   is mapped to 0x00 - 0x5f and SFR page 15 is mapped to 0x60 - 0xff.
;*******************************************************************************
        global  INITMOD, HARDRST, INITVAR, INITTAB, MPTBLP, COPYRIGHT
INITMOD:
; Taken from mcc_generated_files/mcc.c PMD_Initialize
        banksel PMD0
        movlw   0xff                ; Disable all peripheral modules
        movwf   PMD0,b
        movwf   PMD1,b
        movwf   PMD2,b
        movwf   PMD3,b
        movwf   PMD4,b
        movwf   PMD5,b
;        bcf     PMD0,PMD0_SYSCMD_POSN         ; Enable System Clock Network
;        bcf     PMD0,PMD0_NVMMD_POSN          ; Enable NVM Module
;        bcf     PMD0,PMD0_IOCMD_POSN          ; Enable Interrupt on Change
        bcf     SYSCMD              ; Enable System Clock Network
        bcf     NVMMD               ; Enable NVM Module
        bcf     IOCMD               ; Enable Interrupt on Change
; Taken from mcc_generated_files/pin_manager.c
        banksel LATA
        clrf    LATA,b              ; Clear all port output latches
        clrf    LATB,b
        clrf    LATC,b
        setf    TRISA,b
        setf    TRISB,b
        setf    TRISC,b
        banksel ANSELA
        movlw   0xE0                ; Disable unused digital inputs
        movwf   ANSELA,b
        movlw   0xF0
        movwf   ANSELB,b
        movlw   0x00
        movwf   ANSELC,b
        banksel WPUA
        clrf    WPUA,b              ; Disable output pullups
        clrf    WPUB,b
        clrf    WPUC,b
        clrf    WPUE,b
        banksel ODCONA
        clrf    ODCONA,b            ; Outputs source and sink
        clrf    ODCONB,b
        clrf    ODCONC,b
        banksel SLRCONA
        movlw   0xFF                ; Pin slew rate limited (less noise)
        movwf   SLRCONA,b
        clrf    SLRCONB,b           ; Fast slew rate (might help)
        ;movwf   SLRCONB,b
        movwf   SLRCONC,b
        banksel INLVLA
        movlw   0xFF                ; Input level select, ST (CMOS) input
        ;movlw   0x00               ; Input level select, TTL input
        movwf   INLVLA,b
        movwf   INLVLB,b
        movwf   INLVLC,b

        banksel INT0PPS
        movlw   0x04                ; RA4->EXT_INT:INT0
        movwf   INT0PPS,b
        movlw   0x02                ; RA2->EXT_INT:INT1
        movwf   INT1PPS,b

; From data sheet, 2.6 Unused I/Os
        ; Set as output, set low. All LATs have already been cleared
        banksel TRISA
        movlw   0x1f                ; Port A, bits 5-7 output
        andwf   TRISA,b             ; Clear bits 5-7
        movlw   0xcf                ; Port B, bits 4-5 output
        andwf   TRISB,b             ; Clear bits 4-5
        ; Port C eventually connected to SPI SRAM
        movlw   0x00                ; Port C, bits 0-7 output
        andwf   TRISC,b             ; Port C, all output


; Taken from mcc_generated_files/mcc.c OSCILLATOR_Initialize
        movlw   0x60                ; Configure oscillator
        banksel OSCCON1
        movwf   OSCCON1,b
        movlw   0x00
        movwf   OSCCON3,b
        movlw   0x00
        movwf   OSCEN,b
        movlw   0x08
        movwf   OSCFRQ,b
        movlw   0x1F                ; Maximum frequency
        movwf   OSCTUNE,b           ; Recommended by Diego Diaz

        ; Interrupt configuration (CDn fall, Din rise)
; From interrupt_manager.c, INTERRUPT_Initialize()
;        banksel INTCON0
;        bsf     INTCON0,INTCON0_IPEN_POSITION,b       ; Enable Interrupt Priority Vectors
        banksel INTCON
        bsf     IPEN
        banksel IPR0
        bsf     INT0IP              ; INT0I - high priority
        bcf     INT1IP              ; INT1I - low priority
        banksel IOCAF
        ; CDn interrupt on falling edge
        bcf     IOCAF4              ; Interrupt on Change flag
        bsf     IOCAN4              ; Interrupt on negative edge
        bcf     IOCAP4              ; Interrupt on positive edge
        ; Din interrupt on rising edge
        bcf     IOCAF2              ; Interrupt on Change flag
        bcf     IOCAN2              ; Interrupt on negative edge
        bsf     IOCAP2              ; Interrupt on positive edge



; From ext_int.c, EXT_INT_Initialize()
        banksel PIR0
        bcf     INT0IF              ; Clear interrupt flag
        bcf     INT1IF              ; Clear interrupt flag

;        banksel INTCON0
        banksel INTCON
        bcf     INT0EDG             ; Falling edge CDn
        bsf     INT1EDG             ; Rising edge Din

        banksel PIE0
        bsf     INT0IE              ; External interrupts enable
        bsf     INT1IE              ; External interrupts enable

        movlw   0x0f                ; Port B, bits 4-7 output
        andwf   TRISB,f,c           ; Clear bits 4-7

;        bcf     NVMREG0             ; point to Program Flash Memory
;        bsf     NVMREG1             ; access Program Flash Memory

        return
    

;*******************************************************************************
; HARD RESET
; Initialize program variables
;*******************************************************************************
HARDRST:
        banksel CMD                 ; Default for all BSR accesses
        movlw   0x00                ; No ROM configuration is active
        movwf   ROMNUM,c
        ; Initialize static variables
        movlw   ROMLEN              ; Length of ROM configuration string
        mullw   NROMS+1             ; Extra ROM entry for MMIO address
        movff   PRODL,CNTR          ; # of bytes to transfer
        movlw   high(ROM1)          ; ROM string address
        movwf   TBLPTRH,c
        movlw   low(ROM1)
        movwf   TBLPTRL,c
        lfsr    0,ROMDAT            ; Transfer target address
        ;;; 8*N cycles ;;;
HALOOP:
        tblrd   *+
        movf    TABLAT,w,c          ; Transfer FPM byte to WREG
        movwf   POSTINC0,c          ; Store to RAM
        decfsz  CNTR,f,c            ; Done when counter is zero
        bra     HALOOP

        ; Initialize ROM table entry values in RAM
        lfsr    0,ROMDAT            ; Transfer target address
        movlw   NROMS               ; Number of ROM table entries
        movwf   CNTR,c
HALOOP2:
        movlw   teFLAG
        btfsc   PLUSW0,teHARD,0     ; See if we've reached the hard ROM entries
        bra     HAROMS              ; Finish up the two hard rom entries
        movlw   teBANK
        movff   PLUSW0,TEMP         ; Read PFM block number to TEMP
        rrncf   TEMP,c              ; Rotate right 3 times to form ADDR byte
        rrncf   TEMP,c
        rrncf   TEMP,c
        movlw   0x00
        cpfseq  TEMP,c              ; Addressing PFM block 0?
        bra     HA1_7
        movlw   0x10                ; ADDR byte for 8K ROM in block 0
        movwf   TEMP,c
HA1_7:
        movlw   teADDR
        movff   TEMP,PLUSW0         ; Update ADDR byte
        movlw   ROMLEN              ; Length of a ROM table entry
        addwf   FSR0L,f,c           ; Increment to next table entry
        decfsz  CNTR,f,c            ; Done when counter is zero
        bra     HALOOP2
HAROMS:
        movlw   teADDR
        addwf   FSR0L,f,c           ; Bump pointer to ADDR byte of entry
        movlw   0x1c                ; ADDR value for first hard ROM
        movwf   INDF0,c
        movlw   ROMLEN              ; Length of a ROM table entry
        addwf   FSR0L,f,c           ; Increment to next table entry
        movlw   0x1d                ; ADDR value for second hard ROM
        movwf   INDF0,c
        return
    

;*******************************************************************************
; SOFT RESET
; Initialize program variables
;*******************************************************************************

INITVAR:
        banksel CMD                 ; Default for all BSR accesses
        clrf    RDY,c
        clrf    MIOVLD,c
        clrf    IDSENT,c            ; Haven't responded to ID command
        lfsr    0,ROMDAT            ; Point to first ROM entry
        lfsr    1,ROMDAT            ; Point to first ROM entry bank number
        return


;*******************************************************************************
; SOFT RESET 2
; Initialize address mapping table
;*******************************************************************************
INITTAB:
        ; Set up & initialize address mapping table
        lfsr    2,MAPTBL            ; Base address of mapping table
        movlw   0x20                ; 32 table entries
MPTBLP:
        clrf    PLUSW2,0            ; Clear table entry
        decfsz  WREG,c
        bra     MPTBLP
        clrf    PLUSW2,0            ; Clear last table entry
        return

COPYRIGHT:
        db '(', 'c', ')', ' ', 'M', 'a', 'r', 'k'
	db ' ', 'A', '.', ' ', 'F', 'l', 'e', 'm'
	db 'i', 'n', 'g', ' ', '2', '0', '2', '1'
#include "ROMimages.inc"
	END
