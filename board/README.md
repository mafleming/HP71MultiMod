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

## MultiMod Enclosure
Recently added are the STL files for the top and bottom half of the MultiMod
enclosure. Enjoy!

## Press Fit Harwin Sockets
The Sockets.jpg image shows how I press fit the Harwin sockets into a MultiMod
PCB. The three parts of the image show

- (a) The socket holder is a brass piece about 1/4" square. In it are drilled
11 holes 0.15" apart with a #38 or 5/32" drill. The holes are slightly larger
than the socket body and provide a loose fit for the socket tail end.
- (b) I usually start the press fit with the outer six sockets, followed by the
inner five. Note that the socket heads are inserted from the back of the board,
with the socket tails upward from the component side of the PCB.
- (c) Place the board and socket holder in a vise, then press the outer six
sockets for a partial fit. Add the inner five sockets and press all eleven to
final position. Don't press the sockets all the way down, leave about a
fingernail width between the bottom of the socket head and the PCB surface.
This will provide a tight fit in the board without a chance of crushing the
socket body.

The Card Reader pins are 1 mm in diameter. I use the shaft end of a number 61
drill inserted into the socket from the socket head end to clear the sockets
before inserting the board into the Card Reader well.