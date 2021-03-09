HP71MultiMod Repository

# A ROM Emulator Board for the HP-71B
This repository contains the source and data files associated with
the MultiMod ROM emulator board. The board fits into the Card Reader
well of the HP-71B and can be used with an optional enclosure.

The emulator is easily programmed using just a USB to TTL Serial cable.
The emulator can enumerate up to 112 KB of ROM images stored in 7 16 KB
"chips" that can be combined to form ROMs of size 16 KB, 32 KB, 48 KB,
or 64 KB.

Further details on the ROM emulator, how it works and how to use it, can
be found in the User Manual.

# Directory structure
- The **BIN** directory will contain ROM images in .BIN format. For the
moment, images of HP ROMs are not present. ROM images available from and
hosted by others will only be added by permission. Links will be provided
in the meantime.
- The data files containing ROM images can be found in the **DAT** directory.
- The **HEX** directory will contain files that can be used to program the PIC
processor in the MultiMod directly using a Microchip programmer and IPE
software.
- The **LIF** directory contains floppy disk images in HP's proprietary LIF
format. These images contain various useful programs.
- The **doc** directory contains documentation for the MultiMod emulator
as well as for some of the ROM images.
- The **utils** directory contains useful utilities, including python scripts
to convert .BIN files into the .DAT files used by the MultiMod serial monitor.
- The **src** directory contains the MPASM assembly source files used to
program the MultiMod PIC processor. Version 5.35 or earlier of the Microchip
MPLAB IDE X is needed to use the MPASM assembler and linker.