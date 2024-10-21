HP71MultiMod Repository

# A ROM Emulator Board for the HP-71B
This directory contains the Gerber files for creating a MultiMod PCB
along with PDF files of the schematic and BOM. The original design was
created using Eagle CAD 5.0, a PCB design platform that sadly went
extinct quite some years ago.

The board uses SMD parts so you'll either need a reflow oven (I built
one from the Wizzo kit, link below) or have the fine motor skills needed to
solder the parts yourself. The passives are 0805 in size which is
reasonably large for hand soldering. The part numbers given in the BOM are
from Mouser, but you can substitute manufacturer and supplier while
maintaining proper value. No substitute on the PIC CPU unless you know what
you're doing!

https://www.ebay.com/itm/305219966463

Once a board is assembled you'll need to program the PIC CPU using either
a PICKit-3 or PICKit-4 programmer, and the MPLAB X IPE or IDE software.
I developed the code and program PICs using version 5.50, available for
Windows and Linux.

I've used OSH Park as my PCB supplier and OSH Stencil for the solder paste
application.