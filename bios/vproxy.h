#ifndef _VPROXY_H_
#define _VPROXY_H_

#include "portab.h"

#if 0
# define VPROXY_VECTORS ((volatile PFVOID*)0x1C0)
# define VPROXY_NUM_VEC ((0x380 - (ULONG)VPROXY_VECTORS)>>2)
#else
# define VPROXY_NUM_VEC (0x100)
# define VPROXY_VECTORS ((volatile PFVOID*)(STATIC_ALT_RAM_ADDRESS - (VPROXY_NUM_VEC << 2)))
#  if STATIC_ALT_RAM_ADDRESS != 0x01800000UL
#   error This code depends of having some free space below STATIC_ALT_RAM_ADDRESS. Please verify that there is!
#  endif
#endif

extern void vproxy_init(void);

#endif
