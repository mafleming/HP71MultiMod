HP71MultiMod Repository

# A ROM Emulator Board for the HP-71B
HEX files used to program the ROM emulator software using a PICKit
or other PIC programmer will be found here. HEX files containing
the entire PIC flash memory including boot loader are named MMimage
with a four digit version number, while files containing only the
ROM emulator code itself are named MultiMod with a four digit version
number.

Instructions for using the boot loader to update the emulator software
can be found in the User Manual appendix. Files are

- MMimagexxyy.hex     Entire PIC flash image for programming tool
- MultiModxxyy.hex    ROM Emulator software image for bootloader

where xx = major number and yy=minor number.

Version 0103 - fixes ROM table corruption when software flow control is
        not used when sending an image to the serial monitor
Version 0104 - fixes failure to unconfigure ROMs when a RESETX command
        is issued

The file devices.zip contains an updated version of the bootloader client
database of PIC microcontrollers. The PIC18 used in the MultiMod has been
added to the database. Rename the default devices.db and replace it with
the one in this devices.zip file before proceeding with the client update
instructions.