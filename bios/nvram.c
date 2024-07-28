/*
 * nvram.c - Non-Volatile RAM access
 *
 * Copyright (C) 2001-2020 The EmuTOS development team
 *
 * Authors:
 *  LVL     Laurent Vogel
 *
 * This file is distributed under the GPL, version 2 or at your
 * option any later version.  See doc/license.txt for details.
 */

/* #define ENABLE_KDEBUG */

#include "emutos.h"
#include "cookie.h"
#include "machine.h"
#include "vectors.h"
#include "nvram.h"
#include "biosmem.h"
#include "i18nconf.h"
#include "country.h"
#include "nls.h"
#include "ikbd.h"

#if CONF_WITH_NVRAM

#define NVRAM_ADDR_REG  0xffff8961L
#define NVRAM_DATA_REG  0xffff8963L

#define NVRAM_RTC_SIZE  14          /* first 14 registers are RTC */
#define NVRAM_START     NVRAM_RTC_SIZE
#ifdef MACHINE_AMIGA
#define NVRAM_SIZE      100          /* remaining 100 are RAM */
#define NVRAM_USER_SIZE 98          /* of which the user may access 98 */
#else
#define NVRAM_SIZE      50          /* remaining 50 are RAM */
#define NVRAM_USER_SIZE 48          /* of which the user may access 48 */
#endif
#define NVRAM_CKSUM     NVRAM_USER_SIZE /* and the last 2 are checksum */

#ifdef MACHINE_AMIGA
#include "gemdos.h"
UBYTE virtual_nvram[NVRAM_SIZE];
#endif

/*
 * on the TT, resetting NVRAM causes TOS3 to zero it.
 * on the Falcon and FireBee, it is set to zeroes except for a small
 * portion (see below) starting at NVRAM_INIT_START.
 *
 * we do the same to avoid problems booting Atari TOS and EmuTOS on the
 * same system.
 */
#define NVRAM_INIT_START    8
const UBYTE nvram_init[] = { 0x00, 0x2f, 0x20, 0xff, 0xff, 0xff };

int has_nvram;


#ifdef MACHINE_AMIGA
static void save_nvram(void)
{ LONG handle; 
    handle=dos_create("\\GEMSYS\\NVRAM.BIN",0);

    if(handle<=0L)
        handle=dos_create("\\NVRAM.BIN",0);

    if(handle>0L)
    {
        dos_write((WORD) handle, (LONG) NVRAM_SIZE, (void *)virtual_nvram);
        dos_close((WORD)handle);
    }
}

static void read_nvram(void)
{
    LONG handle; 
    handle=dos_open("\\GEMSYS\\NVRAM.BIN",0);
    
    if(handle<=0L)
        handle=dos_open("\\NVRAM.BIN",0);

    if(handle>0L)
    {
        dos_read((WORD) handle, (LONG) NVRAM_SIZE, (void *)virtual_nvram);
        dos_close((WORD)handle);
    }
} 
#endif

static UBYTE read_nvram_byte(int index)
{
    if(index<NVRAM_SIZE)
    {
#ifdef MACHINE_AMIGA
        return virtual_nvram[index];
#else
        volatile UBYTE *addr_reg = (volatile UBYTE *)NVRAM_ADDR_REG;
        volatile UBYTE *data_reg = (volatile UBYTE *)NVRAM_DATA_REG;
        *addr_reg = index + NVRAM_START;
        return *data_reg;
#endif
    }
    return 0;
}



static void write_nvram_byte(int index, UBYTE value)
{
    if(index<NVRAM_SIZE)
    {
#ifdef MACHINE_AMIGA
        virtual_nvram[index]=value;
#else
        volatile UBYTE *addr_reg = (volatile UBYTE *)NVRAM_ADDR_REG;
        volatile UBYTE *data_reg = (volatile UBYTE *)NVRAM_DATA_REG;
        *addr_reg = index + NVRAM_START;
        *data_reg=value;
#endif
    }
}

/*
 * detect_nvram - detect the NVRAM
 */
void detect_nvram(void)
{
#ifndef MACHINE_AMIGA
    if (check_read_byte(NVRAM_ADDR_REG))
        has_nvram = 1;
    else has_nvram = 0;
#else
    has_nvram = 1;
#endif
}

/*
 * get_nvram_rtc - read the realtime clock from NVRAM
 */
UBYTE get_nvram_rtc(int index)
{
    int ret_value = 0;
#ifndef MACHINE_AMIGA
    volatile UBYTE *addr_reg = (volatile UBYTE *)NVRAM_ADDR_REG;
    volatile UBYTE *data_reg = (volatile UBYTE *)NVRAM_DATA_REG;

    if (has_nvram)
    {
        if ((index >= 0) && (index < NVRAM_RTC_SIZE))
        {
            *addr_reg = index;
            ret_value = *data_reg;
        }
    }
#endif

    return ret_value;
}

/*
 * set_nvram_rtc - set the realtime clock in NVRAM
 */
void set_nvram_rtc(int index, int data)
{
#ifndef MACHINE_AMIGA
    volatile UBYTE *addr_reg = (volatile UBYTE *)NVRAM_ADDR_REG;
    volatile UBYTE *data_reg = (volatile UBYTE *)NVRAM_DATA_REG;

    if (has_nvram)
    {
        if ((index >= 0) && (index < NVRAM_RTC_SIZE))
        {
            *addr_reg = index;
            *data_reg = data;
        }
    }
#endif
}

/*
 * compute_sum - internal checksum handling
 */
static UWORD compute_sum(void)
{
    UBYTE sum;
    int i;

    for (i = 0, sum = 0; i < NVRAM_USER_SIZE; i++)
    {
        sum += read_nvram_byte(i);
    }

    return MAKE_UWORD(~sum, sum);
}

/*
 * get_sum - read checksum from NVRAM
 */
static UWORD get_sum(void)
{
    UWORD sum;

    sum = read_nvram_byte(NVRAM_CKSUM)<<8;
    sum |= read_nvram_byte(NVRAM_CKSUM+1);

    return sum;
}

/*
 * set_sum - write checksum to NVRAM
 */
static void set_sum(UWORD sum)
{
    write_nvram_byte(NVRAM_CKSUM,HIBYTE(sum));
    write_nvram_byte(NVRAM_CKSUM+1,LOBYTE(sum));
}

/*
 * nvmaccess - XBIOS read/write/reset NVRAM
 *
 * Arguments:
 *
 *   type   - 0:read, 1:write, 2:reset
 *   start  - start address for operation
 *   count  - count of bytes
 *   buffer - buffer for operations
 */
WORD nvmaccess(WORD type, WORD start, WORD count, UBYTE *buffer)
{
    int i;
#ifdef MACHINE_AMIGA

    const UBYTE skip_count = 2 + CONF_MULTILANG;
    static UBYTE already_load=0;  /* we can set static var with 0 only else it is in rom */
    
    if(already_load<skip_count)
    {
        already_load++;
        if(already_load<skip_count) return -5; /* can't check on first request, file system not available */
        read_nvram();
    }
    
#endif

    if (!has_nvram)
        return 0x2E;

    if (type == 2)      /* reset all */
    {
        for (i = 0; i < NVRAM_USER_SIZE; i++)
        {
            write_nvram_byte(NVRAM_START,0);
        }
        if (cookie_mch == MCH_TT)
            set_sum(compute_sum());
        else
            nvmaccess(1,NVRAM_INIT_START,ARRAY_SIZE(nvram_init),CONST_CAST(UBYTE *,nvram_init));
        return 0;
    }

    if ((buffer == NULL) || (start < 0) || (count < 1) || ((start + count) > NVRAM_USER_SIZE))
        return -5;

    switch(type) {
    case 0:         /* read */
        {
            UWORD expected = compute_sum();
            UWORD actual = get_sum();

            if (expected != actual)
            {
                KDEBUG(("wrong nvram: expected=0x%04x actual=0x%04x\n", expected, actual));
                /* wrong checksum, return error code */
                return -12;
            }
            for (i = start; i < start + count; i++)
            {
                *buffer++ = read_nvram_byte(i);
            }
        }
        break;
    case 1:         /* write */
        for (i = start; i < start + count; i++)
        {
            write_nvram_byte(i,*buffer++);
        }
        set_sum(compute_sum());
#ifdef MACHINE_AMIGA
        save_nvram();
#endif
#if CONF_MULTILANG 
        detect_akp();
        cookie_fix(COOKIE_AKP, cookie_akp);
        font_init();        /* initialize font ring (requires cookie_akp) */
#if CONF_WITH_NLS
        KDEBUG(("nls_init()\n"));
        nls_init();         /* init native language support */
        nls_set_lang(get_lang_name());
#endif
        bioskeys();         /* change table keyboard */
#endif
        break;
    default:
        /* wrong operation code! */
        return -5;
    }

    return 0;
}

#endif  /* CONF_WITH_NVRAM */
