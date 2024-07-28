/*
 * amiga2.S - Amiga specific assembler functions
 *
 * Copyright (C) 2013-2020 The EmuTOS development team
 * Copyright (C) 2020-2023 The EmuTOS/V4 development team
 *
 * Authors:
 *   OL   Olivier Landemarre
 *  PEP   Peter Persson 
 *
 * This file is distributed under the GPL, version 2 or at your
 * option any later version.  See doc/license.txt for details.
 */

#include "asmdefs.h"

#ifdef MACHINE_AMIGA

        .extern _scancode_atari_from_amiga

        .equ    ikbd_acia_stat, 0x00fffc00
        .equ    ikbd_acia_data, 0x00fffc02
        .equ    midi_acia_stat, 0x00fffc04
        .equ    midi_acia_data, 0x00fffc06

        .extern _mouse_report_mv
        .extern _mouse_report_kd_left
        .extern _mouse_report_kd_right
        .extern _mouse_report_ku_left
        .extern _mouse_report_ku_right

        .globl  _mouse_report_relative
        .globl  _mouse_report_absolute
        .globl  _mouse_report_0x74
        .globl  _mouse_report_0x75
        .globl  _mouse_report_0xf4
        .globl  _mouse_report_0xf5
        .globl  _mouse_report_none

        .globl  _joy0_report
        .globl  _joy1_report
        .globl  _joy_monitor

        .extern _play_int_ch0
        .extern _sound_int_call
        .extern _amiga_extra_sound

/******************************************************************************/
/* Startup                                                                    */
/******************************************************************************/

        .globl  amiga_startup
amiga_startup:
        move.l  #0x020000,D0
delay:  subq.l  #1,D0                   // Delay loop.
        jgt     delay

        move.w #0xaaaa,0xdff3fe         // Enable Atari-like features

        // Set up port A on the first CIA (8520-A).

        move.b  #3,0xbfe201             // Set low two bits for output.
        move.b  #2,0xbfe001             // Set boot ROM off, power light dim.

        // Disable interrupts and DMA.

        lea     0xdff000,a0             // Base address of custom chip area.
        move.w  #0x7fff,d0
        move.w  d0,0x9a(a0)             // Disable all interrupts.
        move.w  d0,0x9c(a0)             // Clear all pending interrupts.
        move.w  d0,0x96(a0)             // Disable all DMA.
        bclr.b  #7,0xdaa000             // Disable Gayle interrupts (IDE)
        move.w  #0x8200,0x96(a0)        // DMA Master bit enable

        // Clear CIAA and CIAB
        move.b  #0,0xbfee01             // CIAA control register A
        move.b  #0,0xbfef01             // CIAA control register B
        move.b  #0,0xbfde00             // CIAB control register A
        move.b  #0,0xbfdf00             // CIAB control register B 

        // clear interrupts
        move.b  #0b01111111,0xbfed01    // CIAA interrupt control register: Clear all interrupts
        move.b  #0b01111111,0xbfdd00    // CIAB interrupt control register: Clear all interrupts

        // clear prescalers
        move.b  #0x00,0xbfe401 // CIAA
        move.b  #0x00,0xbfe501
        move.b  #0x00,0xbfe601
        move.b  #0x00,0xbfe701

        move.b  #0x00,0xbfd400 // CIAB
        move.b  #0x00,0xbfd500
        move.b  #0x00,0xbfd600
        move.b  #0x0d,0xbfd700

        move.b #0x83,midi_acia_stat
        move.b #0x00,midi_acia_data

        jmp     (a6)                    // Return

/******************************************************************************/
/* memconf                                                                    */
/* Freely inspired from Markus Wandel's Exec disassembly                      */
/* http://wandel.ca/homepage/execdis/exec_disassembly.txt                     */
/******************************************************************************/

        .globl  amiga_memconf
amiga_memconf:
        lea     0,a0                    // Start looking at location 0.
        lea     0xB80000,a1             // Don't look past this address B80000 11.5MB

checkmem:
        // On entry, A0 is the lower bound of the area to check, and A1 is
        // the high bound.  Memory is checked in 4K blocks.

        moveq   #0,d1
        move.l  d1,(a0)                 // Write a zero to the first location.
        move.l  a0,a2                   // Save the first location.
        move.l  #0xf2d4b698,d0          // Use this as a signature value.

        // Main loop:  We enter here to check each 4K block.

checkmore:
        lea     0x1000(a0),a0           // Increment current location by 4K.
        cmp.l   a0,a1                   // See if upper bound reached.
        jls     exitcheck               // If so, exit from the loop.
        move.l  d0,(a0)                 // Write the signature into memory.

        // Longword 0 of the block being checked was initially cleared to
        // zero.  If it is now no longer zero, we have "wrapped around",
        // i.e. due to incomplete address decoding, we have written the
        // signature value at the beginning of the block.  When this
        // occurs, we have reached the end of memory, even though the
        // signature value would read back correctly.

        tst.l   (a2)                    // Check location 0.
        jne     exitcheck               // Exit if signature appears there.
        cmp.l   (a0),d0                 // See if signature can be read back.
        jeq     checkmore               // If successful, go check more memory.

exitcheck:
        move.l  a0,d5                   // this is phystop - the end of RAM

        //sub.l   #512*1024,d5            // make room for fixed STRAM framebuffer
        //move.l  d5,_stram_screenbuf     //
        moveq   #0x0a,d6                // fake memctrl
        move.b  d6,0xffff8001.w

        jmp     (a6)                    // Return

/******************************************************************************/
/* Interrupt Emulation                                                        */
/******************************************************************************/

        .macro  atari_irq vector, return
                clr.w   -(sp)
                pea \return(pc)
                move.w sr,-(sp)
                jmp ([\vector])
        .endm

/******************************************************************************/
/* ACIA Emulation                                                             */
/******************************************************************************/

acia_ikbd_rx:
        move.b  #0x83,ikbd_acia_stat    // Interrupt, TX empty, RX full
        move.b  d0,ikbd_acia_data

        move.b  #0x40,d0                // ACIA input
        and.b   0xfffffa09.w,d0         // int. enable B
        and.b   0xfffffa15.w,d0         // int. mask B
        jbeq    2$

        atari_irq 0x118.w, 1$

1$:     move.b #0x02,ikbd_acia_stat     // No Interrupt, TX/RX empty
2$:     rts

/******************************************************************************/
/* Interrupt 1: TBE, DISKBLK, SOFTINT                                         */
/******************************************************************************/

        .globl  _amiga_int_1
_amiga_int_1:
        move.l d0,-(sp)

        move.w  0xdff01e,d0             // INTREQR
        and.w   #0x0007,d0              // TBE, DISKBLK or SOFTINT?
        jbeq    int1_end

        move.w  d0,0xdff09c             // Ack interrupts (INTREQ)
        move.w  d0,0xdff09c             // 2CCK delay (propagate IPL from Paula to CPU)

int1_end:
        move.l (sp)+,d0
        rte

/******************************************************************************/
/* Interrupt 2: PORTS (IDE interrupt, but NOT CIAA                            */
/******************************************************************************/

        .globl  _amiga_int_2
_amiga_int_2:
        move.l d0,-(sp)

        move.w  0xdff01e,d0             // INTREQR
        and.w   #0x0008,d0              // PORTS?
        jbeq    int2_end

        move.w  d0,0xdff09c             // Ack interrupts (INTREQ)
        move.w  d0,0xdff09c             // 2CCK delay (propagate IPL from Paula to CPU)

int2_end:
        move.l (sp)+,d0
        rte

/******************************************************************************/
/* Interrupt 3: COPER, VERTB, BLIT (VERTB not generated anymore)              */
/******************************************************************************/

        .globl  _amiga_int_3

_amiga_int_3:
        move.l d0,-(sp)

        move.w  0xdff01e,d0             // INTREQR
        and.w   #0x0070,d0              // COPER, VERTB or BLIT?
        jbeq    int3_end

        move.w  d0,0xdff09c             // Ack interrupts (INTREQ)
        move.w  d0,0xdff09c             // 2CCK delay (propagate IPL from Paula to CPU)

int3_end:
        move.l (sp)+,d0
        rte

/******************************************************************************/
/* Interrupt 4: Atari-like VBL only                                           */
/******************************************************************************/
       .globl  _amiga_int_4
_amiga_int_4: 
        move.l 0x70.w,-(sp)     // jump through Atari VBL vector
        rts

/******************************************************************************/
/* Interrupt 5: RFB, DSKSYNC                                                  */
/******************************************************************************/

        .globl  _amiga_int_5

_amiga_int_5:
        move.l d0,-(sp)

        move.w  0xdff01e,d0             // INTREQR
        and.w   #0x1800,d0              // RFB, DSKSYNC?
        jbeq    int5_end

        move.w  d0,0xdff09c             // Ack interrupts (INTREQ)
        move.w  d0,0xdff09c             // 2CCK delay (propagate IPL from Paula to CPU)

int5_end:
        move.l (sp)+,d0
        rte

/******************************************************************************/
/* Interrupt 6: EXTER (CIAA and CIAB)                                          /
/******************************************************************************/

       .globl  _amiga_int_6

_amiga_int_6:
        movem.l d0-d2/a0-a1,-(sp)
        move.w #0x2700,sr

        move.w  0xdff01e,d0             // INTREQR
        btst    #13,d0                  // EXTER interrupt?
        jbeq    exter_skip

        move.b  0xbfdd00,d0             // CIAB?
        jbpl    kbd

        btst    #0,d0
        jbeq    kbd                     // bit 0 not set means no Timer A interrupt

        jbsr    eval_mouse_joy

kbd:    move.b  0xbfed01,d0             // CIAA?
        jbpl    kbd_done

        btst    #3,d0
        jbeq    kbd_done                // bit 3 not set means no serial interrupt

        jbsr    eval_kbd

kbd_done:

        move.w  #0x2000,0xdff09c                 // Ack EXTER (INTREQ)
        move.w  #0x2000,0xdff09c                 // 2CCK delay (propagate IPL from Paula to CPU)

exter_skip:
        movem.l (sp)+,d0-d2/a0-a1
        rte

/******************************************************************************/
/* I2C RTC                                                                    */
/******************************************************************************/

// a CIA address, needed for the delay loops:
        .equ CIABPRA, 0xBFD000
        .equ I2CDAT, 0xDE0080

// What I/O lines do we use?
// SCL out: bit1 \_ in the word (!) at the
// SDA out: bit0 /  base address of our board
// SDA in:  bit0  of the same address

        .macro INITPORT
        lea I2CDAT,a1
        move.w #3,(a1)
        .endm

        .macro ALLOCPERCALL
        .endm
        .macro RELEASEPERCALL
        .endm

        .macro PREP4MACROS
        lea CIABPRA,a0
        lea I2CDAT,a1
        moveq #3,d7
        .endm

        .macro SCLH
        bset #1,d7
        move.w d7,(a1)
        .endm

        .macro SCLL
        bclr #1,d7
        move.w d7,(a1)
        .endm

        .macro SDAH
        bset #0,d7
        move.w d7,(a1)
        .endm

        .macro SDAL
        bclr #0,d7
        move.w d7,(a1)
        .endm

        .macro SDAtest
        btst #0,1(a1)
        .endm

        .macro IDLEREAD
        tst.b (a0)
        .endm

        .globl _amiga_sendI2C
_amiga_sendI2C:
        movem.w 4(sp),d0                // slave address
        movem.w 6(sp),d1                // number of bytes
        move.l  8(sp),a1                // buffer to be sent
        movem.l d2-d7/a2,-(sp)
        move.l a1,a2

        moveq.l #127,d5                 // delay

        bsr prepare
        move.w d1,d6                    // backup, because D1 will be destroyed
        bclr #0,d0                      // make the address "write" style
        bsr start_bit
.SendLoop:                              // Send the byte in D0
        bsr NineBitIO
        moveq #0,d3                     // defaut OK=0
        sub.b d2,d0
        bne HardErr                     // That's not what we sent!
        tst.w d2
        bmi AckErr                      // ACK bit "1", that means "NAK"
        subq.w #1,d1
        bmi EndIO                       // all done
        move.b (a2)+,d0                 // else get a byte from the buffer
        bra.s .SendLoop

AckErr: cmp.w d1,d6                     // if this was the 1st (=address) byte,
        beq NoReply                     // this is the classical "bad address" error
        moveq #0,d3                     // "NAK" might still be "OK",
        tst.w d1                        // if this were the last byte anyway
        beq EndIO                       // yes
        moveq #-1,d3                    // else: error "data rejected"
        bra EndIO
    
prepare:
        PREP4MACROS
        bset #15,d0                     // always enable reading the ACK bit
        rts

start_bit:
        SDAL
        bsr BigDelay
        SCLL
        bsr BigDelay                    // NineBitIO starts without DELAY
        rts

BigDelay:
        move.l d5,d4
        addq.l #1,d4
        asl.l #1,d4
        beq.s .bexit
.wait:
        tst.b (a0)
        subq.l #1,d4
        bne.s .wait
.bexit:
        rts

         
         .globl _amiga_recvI2C  
_amiga_recvI2C:
        movem.w 4(sp),d0                // slave address
        movem.w 6(sp),d1                // number of bytes
        move.l  8(sp),a1                // buffer to store bytes
        movem.l d2-d7/a2,-(sp)
        move.l a1,a2

        moveq.l #127,d5                 // delay

        bsr prepare
        bset #0,d0                      // make the address "read" style

        bsr start_bit
        // Send the address byte first (is found in D0)
        bsr NineBitIO
        cmp.b d2,d0
        bne HardErr                     // That's not what we sent!
        tst.w d2
        bmi NoReply                     // Adress got no reply!
        // Now we can receive data, but remember:
        // We must receive 1 byte at least, even if 0 were requested.
.RecvLoop:
        moveq #-1,d0                    // enable reading 8 bits,
        subq.w #1,d1                    // count the byte
        ble.s .rlb0
        lsr.w #1,d0                     // always ACK=0, except last byte
.rlb0:
        bsr NineBitIO
        tst.w d1                        // Was this the 1st of 0 bytes?
        bmi.s .rlb2                     // Yes, don't store it, just quit.
        move.b d2,(a2)+                 // Else store the byte to the buffer.
        tst.w d1
        bne.s .RecvLoop                 // Any more to receive?
.rlb2:
        moveq #0,d3
        bra EndIO                       // all done

        // these are jumped to (!) at the end of both Send and Receive:
NoReply:
        moveq #-5,d3                    // error: "no reply"
        bra EndIO
HardErr:                                // encountered a real bad hardware error
        moveq #-2,d3                    // Suppose "SDA always HI",
        cmp.b #0xFF,d2                  // is that so?
        beq EndIO                       // yes
        moveq #-3,d3                    // Well then, "SDA always LO"?
        tst.b d2
        beq EndIO                       // yes
        moveq #-4,d3                    // "SDA trashed" in no specific way
EndIO:
        // stop the bus,
        // stop condition is CLK=L->H, wait>=4.7µs, DATA=L->H, wait>=4.7µs
        // ("protocol violation to HI")
        SDAL                            // make sure DATA is LO
        bsr BigDelay
        SCLH
        bsr BigDelay
        SDAH
        bsr BigDelay                    // ensure a minimum "bus free" time

        move.l d3,d0
        movem.l (sp)+,d2-d7/a2
        rts
        
wait:
        beq.s .wexit
.wait0:
        tst.b (a0)
        subq.l #1,d4
        bne.s .wait0    
.wexit:
        rts
        
NineBitIO:
        // ACK bit (#15): send 9 bits from D0 and monitor SDA line to return
        // a 9 bit "echo" in D2.
        // The required minimum timing can be guaranteed from the number of
        // CIA R/W accesses (i. e. EClock-cycles). CLK=HI: 3 cycles -> 4.2µs,
        // CLK=LO: 4 cycles -> 5.6µs.
        rol.w #1,d0                     // put ACK bit in a more convenient place
        clr.w d2                        // echo-"byte"
        moveq #8,d3                     // 9 bit
.BitLoop:
        move.l d5,d4
        lsr.l #1,d4
        bsr wait
        btst d3,d0
        beq.s .nlb1
        SDAH                            // send "1"
        bra.s .nlb2
.nlb1:
        SDAL                            // send "0"
.nlb2:
        move.l d5,d4
        addq.l #1,d4
        lsr.l #1,d4
        bsr wait
        SCLH                            // CLK-pulse (>=4.0µs) to indicate
        move.l d5,d4
        bsr wait
        SDAtest
        beq.s .nlb3                      // SDA LO?
        bset d3,d2                      // else set the according "echo-bit"
.nlb3:
        SCLL                            // CLK=LO (>=4.7µs) to prepare for
        dbf d3,.BitLoop                 // the next bit
        ror.w #1,d0                     // undo the shifting
        ror.w #1,d2                     // same for the echo byte
        rts


eval_kbd:
        move.b  0xbfec01,d0             // read character
        bset    #6,0xbfee01             // start ack
        ror.b   #1,D0
        not.b   D0
        moveq   #50,D1
wack:   tst.b   0xbfe001
        dbra    D1,wack
        bclr    #6,0xbfee01

        move.b  d0,d1
        andi.b  #0x80,d0
        andi.w  #0x007f,d1
        lea     _scancode_atari_from_amiga,a0
        or.b    0(a0,d1.w),d0

        jsr     acia_ikbd_rx

        rts

eval_mouse_joy:
        lea.l _mouse_report_none(pc),a1
        move.w 0xdff00a,d0
        move.w _olddeltas,d1

        cmp.w d0,d1
        jbeq no_movement

        move.w d0,_olddeltas
        sub.b d1,d0
        move.b d0,d2
        ext.w d2
        add.w _mousex,d2
        tst.w d2
        jbge noclipxmin
        moveq #0,d2
noclipxmin:
        cmp.w _mousexmax,d2
        jble noclipxmax
        move.w _mousexmax,d2
noclipxmax:
        move.w d2,_mousex

        rol.w #8,d1
        rol.w #8,d0
        sub.b d1,d0
        move.b d0,d2
        ext.w d2
        add.w _mousey,d2

        tst.w d2
        jbge noclipymin
        moveq #0,d2
noclipymin:
        cmp.w _mouseymax,d2
        jble noclipymax
        move.w _mouseymax,d2
noclipymax:
        move.w d2,_mousey

        move.w d0,_newdeltas

        move.l _mouse_report_mv,a1

no_movement:
        move.b   0xbfe001,d0 | joystick 1 fire button at bit 7
        lsl.w    #3,d0
        and.w    0xdff016,d0 | right mouse button at bit 10
        move.b   0xbfe001,d0 | left mouse button at bit 6

        and.w  #0x0440,d0
        move.w _oldbuttons,d1

        cmp.w d0,d1
        jbeq no_buttons

        move.w d0,_oldbuttons
        eor.w  d0,d1

buttons_changed:
        move.w d0,_oldbuttons

        btst #6,d1 | left key changed?
        jbeq left_end

        btst #6,d0
        jbne left_down

left_up:
        bset.b #2,_absbuttons
        move.l _mouse_report_ku_left,a0
        jsr (a0)
        jbra left_end
left_down:
        bset.b #3,_absbuttons
        move.l _mouse_report_kd_left,a0
        jsr (a0)
left_end:

        btst #10,d1 | right key changed?
        jbeq right_end

        btst #10,d0
        jbne right_down
right_up:
        bset.b #0,_absbuttons
        move.l _mouse_report_ku_right,a0
        jsr (a0)
        jbra right_end
right_down:
        bset.b #1,_absbuttons
        move.l _mouse_report_kd_right,a0
        jsr (a0)
right_end:
        move.l _mouse_report_mv,a1

no_buttons:
        jsr (a1)

        move.l _joy0_report,a0
        jsr (a0)
        move.l _joy1_report,a0
        jsr (a0)
        move.l _joy_monitor,a0
        jsr (a0)
        move.l _joy_interrogate,a0
        jsr (a0)
        rts

buttons: |; this code isn't used yet. Idea is:
         |; - consolidate all button crap to here so
         |;   that right mouse button + joy1 fire is one and the same.

        move.b   0xbfe001,d0 | b6 = left mouse button, fire button joy 0
        lsl.w    #2,d0       
        move.b   0xdff016,d0 | b2 = right mouse button
        lsl.b    #5,d0
        and.b    0xbfe001,d0 | b7 = fire button joy 0

        lsr.w    #1,d0
        eor.b    #0xc0,d0

        rts

        .extern _olddeltas
        .extern _oldbuttons
        .extern _newdeltas
        .extern _absbuttons

_mouse_report_relative:
        move.w _oldbuttons,d0
        lsr.b #6,d0 | 0x0401
        lsl.w #5,d0 | 0x8020
        lsr.b #5,d0 | 0x8001
        rol.w #1,d0
        eor.b #3,d0

        or.b  #0xf8,d0
        jsr acia_ikbd_rx

        move.w _newdeltas,d0
        rol.w #8,d0
        jsr acia_ikbd_rx

        lsr.w #8,d0
        jsr acia_ikbd_rx

        rts

_mouse_report_absolute:
        move.w sr,-(sp)
        move.w #0x2700,sr

        moveq #(0xf7-0x100),d0
        jsr acia_ikbd_rx

        move.b _absbuttons,d0
        jsr acia_ikbd_rx

        clr.b _absbuttons

        move.w _mousex,d0
        rol.w #8,d0
        jsr acia_ikbd_rx

        rol.w #8,d0
        jsr acia_ikbd_rx

        move.w _mousey,d0
        rol.w #8,d0
        jsr acia_ikbd_rx

        rol.w #8,d0
        jsr acia_ikbd_rx

        move.w (sp)+,sr
        rts

_mouse_report_0x74:
        moveq #0x74,d0
        jsr acia_ikbd_rx
        rts

_mouse_report_0x75:
        moveq #0x75,d0
        jsr acia_ikbd_rx
        rts

_mouse_report_0xf4:
        moveq #(0xf4-0x100),d0
        jsr acia_ikbd_rx
        rts

_mouse_report_0xf5:
        moveq #(0xf5-0x100),d0
        jsr acia_ikbd_rx
        rts

_mouse_report_none:
        rts

        .globl _joy_interrogate_on
_joy_interrogate_on:
        move.l #_joy_interrogate_off,_joy_interrogate |; execute once

        move.b   #0xfd,d0
        jsr      acia_ikbd_rx

        btst     #6,0xbfe001 |; joystick 0 button
        seq      d1
        and.b    #0x80,d1

        move.w   0xdff00a,d0
        jbsr     joydir
        or.b     d1,d0
        jsr      acia_ikbd_rx

        move.b   0xdff016,d1  |; right mouse button at bit 2
        lsl.b    #5,d1
        and.b    0xbfe001,d1  |; joystick 1 button
        and.b    #0x80,d1
        eor.b    #0x80,d1

        move.w   0xdff00c,d0
        jbsr     joydir
        or.b     d1,d0
        jsr      acia_ikbd_rx

        rts

        .globl _joy_monitor_on
_joy_monitor_on:
        move.b   0xbfe001,d0  |; joystick 0/1 buttons
        move.b   0xdff016,d2  |; right mouse button at bit 2
        lsl.b    #5,d2
        and.b    d0,d2        |; joystick 1 button

        btst     #6,d0        |; joystick 0 button
        seq      d0
        add.w    d0,d0

        btst     #7,d2
        seq      d0
        add.w    d0,d0

        rol.w    #8,d0
        and.b    #3,d0

        jbsr     acia_ikbd_rx |; report buttons

        move.w   0xdff00a,d0
        jbsr     joydir
        move.b   d0,d1

        move.w   0xdff00c,d0
        jbsr     joydir

        lsl.b    #4,d1
        or.b     d1,d0

        jbsr     acia_ikbd_rx |; report directions
        rts

joydir: ror.b    #2,d0
        lsr.w    #6,d0
        and.w    #0xf,d0
        move.b   conv(pc,d0.w),d0
        rts

conv:   dc.b     0, 2, 10, 8, 1, 0, 8, 9, 5, 4, 0, 1, 4, 6, 2, 0

        .extern _oldjoy0dat
        .extern _oldjoy1dat

        .globl _joy0_report_event
_joy0_report_event:
        btst     #6,0xbfe001
        seq      d2
        and.b    #0x80,d2

        move.w   0xdff00a,d0
        jbsr     joydir

        or.b     d0,d2     

        cmp.b    _oldjoy0dat,d2
        jbeq     joy0done

        move.b   d2,_oldjoy0dat

        move.b   #0xff,d0
        jbsr     acia_ikbd_rx

        move.b   d2,d0
        jbsr     acia_ikbd_rx   
joy0done:
        rts

        .globl _joy1_report_event
_joy1_report_event:
        move.b   0xdff016,d2  |; right mouse button at bit 2
        lsl.b    #5,d2
        and.b    0xbfe001,d2  |; joystick 1 button
        and.b    #0x80,d2
        eor.b    #0x80,d2

        move.w   0xdff00c,d0
        jbsr     joydir

        or.b     d0,d2     

        cmp.b    _oldjoy1dat,d2
        jbeq     joy1done

        move.b   d2,_oldjoy1dat

        move.b   #0xff,d0
        jbsr     acia_ikbd_rx

        move.b   d2,d0
        jbsr     acia_ikbd_rx   
joy1done:
        rts

        .globl _joy0_report_off
_joy0_report_off:
        .globl _joy1_report_off
_joy1_report_off:
        .globl _joy_monitor_off
_joy_monitor_off:
        .globl _joy_interrogate_off
_joy_interrogate_off:
        rts
#endif
