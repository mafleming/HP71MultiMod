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