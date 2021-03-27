HP71MultiMod Repository

# A ROM Emulator Board for the HP-71B
** 27-March-2021 **

Source files for the current production release of the MultiMod board. These files
are assembled, linked, and loaded with MPASMX in MicroChip MPLAB X IDE v5.35,
which can be obtained from Microchip.com in their development tools repository.

# Errata
Issues that will be addressed in maintenance and enhancement releases are listed here.

- Carriage return for the Commit command should default to NO rather than YES.
- Detect buffer overrun and terminate ROM image upload for Image command.
- Display software version number in serial monitor.
- Display ROM name in ROM Configuration Table listing.
- Locate serial monitor on sector boundary so it can be updated separately from emulator.
- Allow readback (PEEK$) of MMIO configuration buffer data.
- Make timeout to processor sleep state configurable by user (current default 2.5 minutes).
