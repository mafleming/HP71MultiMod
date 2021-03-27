;*******************************************************************************
; Configuration Constants
; Each of the first seven entries in this table describe a soft or hard ROM.
; Each entry consists of
;  Five nibble ID, Flag byte, Addr byte, Program Flash Memory Bank (ROMBANK)
;
; Soft ROMs are described in the first table entries, and they end when the
; Flag byte is non-zero.
; Each ID nibble is stored in a byte, starting with the first nibble.
; PFM Bank is between 1 and 7.
;
; Hard ROMs, if any, follow the last soft ROM entry. They use the Flag and Addr
; bytes.
;  The Flag byte indicates whether the entry is inactive (0) or active (ff).
;  The Addr byte is used to address the lookup table that defines where the
;  ROM appears in the Saturn address space. The values can be 0x1c & 0x1d for
;  base address E0000h or 0x00 & 0x01 for base address 00000h.
; 
; Found out that the number of DB bytes per ROM config string MUST BE EVEN!
; An odd length ends up padding the extra byte with zero.
; Size of constant section must be a multiple of sector size (128 Words,
; 256 bytes) so the sector can be erased before written to.
;*******************************************************************************

; ROMs enumerated according to size
        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 1 ; 16K forth
        DB  0x09, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 2 ; 32K math2b
        DB  0x09, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 4 ; 32K jpc05
        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x01, 0x00, 0 ; 16K ulib52
        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 5 ; Empty
        ; Hard configured ROM must be in last two entries
        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 6 ; 32K forthhrd
        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 7 ; 32K forthhrd
        DB  0x00, 0x00, 0x00, 0x0c, 0x02, 0x00, 0x00, 0 ; MMIO address
; ROMs enumerated as 16K chips
;        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 1 ; 16K forth
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 2 ; 32K math2b
;        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 3 ; 32K math2b
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 4 ; 32K jpc05
;        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x01, 0x00, 5 ; 32K jpc05
        ; Hard configured ROM must be in last two entries
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 6 ; 32K forthhrd
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 7 ; 32K forthhrd
;        DB  0x00, 0x00, 0x00, 0x0c, 0x02, 0x00, 0x00, 0 ; MMIO address

; ROMs enumerated according to size, with an MMIO
;        DB  0x0e, 0x00, 0x0f, 0x01, 0x0c, 0x00, 0x00, 0 ; MMIO
;        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 1 ; 16K forth
;        DB  0x09, 0x01, 0x01, 0x00, 0x08, 0x00, 0x00, 2 ; 32K math2b
;        DB  0x09, 0x02, 0x01, 0x00, 0x08, 0x00, 0x00, 4 ; 32K jpc05
;        DB  0x0a, 0x00, 0x01, 0x00, 0x08, 0x01, 0x00, 0 ; 16K ulib52
        ; Hard configured ROM must be in last two entries
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 6 ; 32K forthhrd
;        DB  0x0a, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 7 ; 32K forthhrd
;        DB  0x00, 0x00, 0x00, 0x0c, 0x02, 0x00, 0x00, 0 ; MMIO address

;*******************************************************************************
; ROM IMAGES
; ROM images begin in block 1, address 04000h and can occupy flash memory up to
; beginning address 1C000. A hard configured ROM could go anywhere, but by
; convention is placed in the last two blocks, addressed from 18000h to 1FFFFh.
;*******************************************************************************
        org 0x02000
#include ulib52.inc
        org 0x04000
;#include hp41trans.inc
#include forth1b.inc
        org 0x08000
#include math2b7.inc
        org 0x10000
#include jpc05.inc
        org 0x18000
;#include hp41transhrd.inc
#include forth1bhrd.inc



