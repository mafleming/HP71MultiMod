;*******************************************************************************
; ROM IMAGES
; ROM images begin in block 1, address 04000h and can occupy flash memory up to
; beginning address 1C000. A hard configured ROM could go anywhere, but by
; convention is placed in the last two blocks, addressed from 18000h to 1FFFFh.
;*******************************************************************************
        org 0x02000
#include "ulib52.inc"
        org 0x04000
;#include "hp41trans.inc"
#include "forth1b.inc"
        org 0x08000
#include "math2b7.inc"
        org 0x10000
#include "jpcf05.inc"
        org 0x18000
;#include "hp41transhrd.inc"
#include "forth1bhrd.inc"
