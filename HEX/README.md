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