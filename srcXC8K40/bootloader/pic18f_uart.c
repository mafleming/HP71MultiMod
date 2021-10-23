/*
    (c) 2019 Microchip Technology Inc. and its subsidiaries. 
    
    Subject to your compliance with these terms, you may use Microchip software and any 
    derivatives exclusively with Microchip products. It is your responsibility to comply with third party 
    license terms applicable to your use of third party software (including open source software) that 
    may accompany Microchip software.
    
    THIS SOFTWARE IS SUPPLIED BY MICROCHIP "AS IS". NO WARRANTIES, WHETHER 
    EXPRESS, IMPLIED OR STATUTORY, APPLY TO THIS SOFTWARE, INCLUDING ANY 
    IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY, AND FITNESS 
    FOR A PARTICULAR PURPOSE.
    
    IN NO EVENT WILL MICROCHIP BE LIABLE FOR ANY INDIRECT, SPECIAL, PUNITIVE, 
    INCIDENTAL OR CONSEQUENTIAL LOSS, DAMAGE, COST OR EXPENSE OF ANY KIND 
    WHATSOEVER RELATED TO THE SOFTWARE, HOWEVER CAUSED, EVEN IF MICROCHIP 
    HAS BEEN ADVISED OF THE POSSIBILITY OR THE DAMAGES ARE FORESEEABLE. TO 
    THE FULLEST EXTENT ALLOWED BY LAW, MICROCHIP'S TOTAL LIABILITY ON ALL 
    CLAIMS IN ANY WAY RELATED TO THIS SOFTWARE WILL NOT EXCEED THE AMOUNT 
    OF FEES, IF ANY, THAT YOU HAVE PAID DIRECTLY TO MICROCHIP FOR THIS 
    SOFTWARE.
*/

#define  STX   0x55

#define  READ_VERSION   0
#define  READ_FLASH     1
#define  WRITE_FLASH    2
#define  ERASE_FLASH    3
#define  READ_EE_DATA   4
#define  WRITE_EE_DATA  5
#define  READ_CONFIG    6
#define  WRITE_CONFIG   7
#define  CALC_CHECKSUM  8
#define  RESET_DEVICE   9

#include <xc.h>
#include <stdint.h>
#include <stdbool.h>
#include "bootload.h"
#include "mcc.h"

uint8_t RdData ();
void    WrData (uint8_t  data);
frame_t  frame;
// *****************************************************************************
//Autobaud:
//
// ___     ___     ___     ___     ___     __________
//    \_S_/ 1 \_0_/ 1 \_0_/ 1 \_0_/ 1 \_0_/ Stop
//       |                                |
//       |-------------- p ---------------|
//
// EUSART autobaud works by timing 4 rising edges (0x55).  It then uses the
// timed value as the baudrate generator value.
// *****************************************************************************
void Run_Bootloader()
{
    volatile uint16_t  index;
    uint16_t  msg_length;

    while (1)
    {
        while (TX1STAbits.TRMT == 0); // wait for last byte to shift out before
                                 // starting autobaud.
        Check_Device_Reset ();  // Response has been sent.  Check to see if a reset was requested

// *****************************************************************************
// Hardware AutoBaud
// *****************************************************************************
//        BAUDCONbits.ABDEN = 1;    // start auto baud
//        while (BAUDCONbits.ABDEN == 1)
//        {
//            if (BAUDCONbits.ABDOVF == 1)
//            {
//                BAUDCONbits.ABDEN = 0;    // abort auto baud
//                BAUDCONbits.ABDOVF = 0;    // start auto baud
//                BAUDCONbits.ABDEN = 1;    // restart auto baud
//            }
//        }

        index = EUSART1_Read();  // required to clear RCIF
// *****************************************************************************

// *****************************************************************************
// Read and parse the data.
        index = 0;       // Point to the buffer
        msg_length = 9;  // message has 9 bytes of overhead (Opcode + Length + Address)
        uint8_t  ch;

        while (index < msg_length)
        {
            ch = EUSART1_Read();          // Get the data
            frame.buffer [index ++] = ch;
            if (index == 4)
            {
                if ((frame.command == WRITE_FLASH)
                 || (frame.command == WRITE_EE_DATA)
                 || (frame.command == WRITE_CONFIG))
                {
                    msg_length += frame.data_length;
                }
            }
        }

        msg_length = ProcessBootBuffer ();

// *****************************************************************************
// Send the data buffer back.
// *****************************************************************************
        EUSART1_Write(STX);
        index = 0;
        while (index < msg_length)
        {
            EUSART1_Write (frame.buffer [index++]);
        }
    }
}
// *****************************************************************************


