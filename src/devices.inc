
#ifdef __18F27Q10
     #define DEVICEID                .904
     #define WRITE_FLASH_BLOCKSIZE   .256
     #define ERASE_FLASH_BLOCKSIZE   .256
     #define END_FLASH               0x20000
     #define END_GPR                 0xE00
     #define BOOTBLOCKSIZE           0x800
#endif
#ifdef __18F27K40
     #define DEVICEID                .843
     #define WRITE_FLASH_BLOCKSIZE   .128
     #define ERASE_FLASH_BLOCKSIZE   .128
     #define END_FLASH               0x20000
     #define END_GPR                 0xE88
     #define BOOTBLOCKSIZE           0x800
#endif
