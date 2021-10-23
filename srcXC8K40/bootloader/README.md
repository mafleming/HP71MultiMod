HP71MultiMod Repository

# A ROM Emulator Board for the HP-71B
**23-October-2021**
Source files for the MultiMod board bootloader. These files
are assembled, linked, and loaded with pic-as v2.32 in MicroChip MPLAB X IDE v5.45.
The assembler is part of the XC8 development compiler. MPLAB X and XC8
can be obtained from Microchip.com in their development tools repository.

This port of the MultiMod application code from MPASM to pic-as has been done
for two reasons; MPASM is no longer supported by Microchip, and the pic-as
assembler is needed to transfer code to more recent PIC microcontrollers.

# Build Instructions
First create a standalone application project with the suggested name of
BootLoaderK40. Copy the main.c file from the bootloader subdirectory to the base
directory of the project. Copy all other files to the mcc_generated_files
subdirectory. Be sure to specify the target processor as PIC18F27K40, then build
the project. The .hex file needed by the MultiMod application project can be found
in the dist/default/production subdirectory.
