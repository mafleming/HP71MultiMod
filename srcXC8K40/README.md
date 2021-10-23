HP71MultiMod Repository

# A ROM Emulator Board for the HP-71B
**23-October-2021**

Source files for the MultiMod board. These files
are assembled, linked, and loaded with pic-as v2.32 in MicroChip MPLAB X IDE v5.45.
The assembler is part of the XC8 development compiler. MPLAB X and XC8
can be obtained from Microchip.com in their development tools repository.

This port of the MultiMod application code from MPASM to pic-as has been done
for two reasons; MPASM is no longer supported by Microchip, and the pic-as
assembler is needed to transfer code to more recent PIC microcontrollers.

# Build Instructions
First create a standalone application project with the suggested name of
MultiModK40. Copy all  files to the base project directory.
In the Project Configuration dialog under Loading, add the
BootLoaderK40.X.production.hex file.
Be sure to specify the target processor as PIC18F27K40, then build
the project.

# Errata
Maintenance issues that are addressed are listed here.

- Carriage return for the Commit command defaults to NO rather than YES.
- Detect buffer overrun and terminate ROM image upload for Image command.
