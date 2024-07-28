#include "portab.h"
#include "config.h"
#include "vproxy.h"

#if CONF_WITH_VECTOR_PROXY

#if CONF_WITH_APOLLO_68080
# define CODE(vec_num) { 0x4ef0, 0x01e1, (vec_num) << 2 } /* jmp [(vec_num<<2.w)] */
#else
# define CODE(vec_num) { 0x2f38, (vec_num) << 2, 0x4e75 } /* move.l vec_num<<2.w,-sp; rts */
#endif

#define CODE_BLOCK16(vec_base) \
CODE((vec_base) + 0 ), CODE((vec_base) + 1 ), CODE((vec_base) + 2 ), CODE((vec_base) + 3 ), \
CODE((vec_base) + 4 ), CODE((vec_base) + 5 ), CODE((vec_base) + 6 ), CODE((vec_base) + 7 ), \
CODE((vec_base) + 8 ), CODE((vec_base) + 9 ), CODE((vec_base) + 10), CODE((vec_base) + 11), \
CODE((vec_base) + 12), CODE((vec_base) + 13), CODE((vec_base) + 14), CODE((vec_base) + 15)

static const UWORD proxy_handlers[256][3] =
{
    CODE_BLOCK16(16 * 0 ), CODE_BLOCK16(16 * 1 ), CODE_BLOCK16(16 * 2 ), CODE_BLOCK16(16 * 3 ),
    CODE_BLOCK16(16 * 4 ), CODE_BLOCK16(16 * 5 ), CODE_BLOCK16(16 * 6 ), CODE_BLOCK16(16 * 7 ),
    CODE_BLOCK16(16 * 8 ), CODE_BLOCK16(16 * 9 ), CODE_BLOCK16(16 * 10), CODE_BLOCK16(16 * 11),
    CODE_BLOCK16(16 * 12), CODE_BLOCK16(16 * 13), CODE_BLOCK16(16 * 14), CODE_BLOCK16(16 * 15),
};

void vproxy_init(void)
{   int i;

    for(i = 0; i < VPROXY_NUM_VEC; i++)
        VPROXY_VECTORS[i] = (void*)&proxy_handlers[i];

    __asm__ volatile
    (
        "move.l %0,d0\n\t"
        "dc.w 0x4e7b, 0x0801\n" /* movec d0,VBR */
    : /* outputs */
    : "g"((void*)VPROXY_VECTORS) /* inputs  */
    : __CLOBBER_RETURN("d0")  /* clobbered regs */
    );
}

#endif
