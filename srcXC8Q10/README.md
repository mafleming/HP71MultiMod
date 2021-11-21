MultiModII.X

These source files are suitable for the PIC18F2-Q10 family of processors. The
low power requirements of the Q10 make it suitable for a front port module
implementation. The bootloader and serial port monitor code has been removed.
ROM images and code would be updated using a PICKit-3 or better programmer.

The project is built in a similar way as the main MultiMod code in the src/
subdirectory. Instead of the MPASM assembler, the pic-as assembler in the XC8
compiler package is used. Use the MPLAB X IDE version 5.45 or higher. Create
a standalone project, select the PIC18F27Q10 as the target processor, select the
pic-as assembler as the build tool, and then add these files to the Source Files
folder of the project directory tree in the IDE. Assemble, Link, then program
using a PICKit-3 or PICKit-4 programmer.