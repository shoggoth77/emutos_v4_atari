#if CONF_WITH_VAMPIRE_SPI


	.globl	_spi_clock_sd
_spi_clock_sd:
	move.w	#0x01,0xDE000C	/* 25 MHz */
	rts


	.globl	_spi_clock_mmc
_spi_clock_mmc:
	move.w	#0x02,0xDE000C	/* 16.7 MHz */
	rts


	.globl	_spi_clock_ident
_spi_clock_ident:
	move.w	#0xff,0xDE000C	/* 195 kHz */
	rts


	.globl	_spi_cs_assert
_spi_cs_assert:
	lea.l	0xDE0000,a0
	clr.w	4(a0)
	st.b	(a0)
	tst.b	(a0)
	rts


	.globl	_spi_initialise
_spi_initialise:
	/* fallthrough */

	.globl	_spi_cs_unassert
_spi_cs_unassert:
	lea.l	0xDE0000,a0
	move.w	#1,4(a0)
	st.b	(a0)
	tst.b	(a0)
	rts


	.globl	_spi_send_byte
_spi_send_byte:
	lea.l	0xDE0000,a0
	move.b	5(sp),(a0)
	tst.b	(a0)
	rts


	.globl	_spi_recv_byte
_spi_recv_byte:
	lea.l	0xDE0000,a0
	st.b	(a0)
	move.b	(a0),d0
	rts


	.globl	_spi_recv_block
_spi_recv_block:
	move.l	4(sp),a0
	movem.w	8(sp),d0
	lea.l	0xDE0002,a1
	tst.l	d0
	jbeq	3$

	st.b	-2(a1)
	subq.l	#1,d0
	tst.l	a0
	jbeq	5$

	jbra	2$
1$:	move.b	(a1),(a0)+
2$:	dbra	d0,1$
	move.b	-2(a1),(a0)+
3$:	rts

4$:	tst.b	(a1)
5$:	dbra	d0,4$
	tst.b	-2(a1)
	rts


	.globl	_spi_send_block
_spi_send_block:
	move.l	4(sp),a0
	movem.w	8(sp),d0
	lea.l	0xDE0000,a1
	tst.l	d0
	jbeq	3$

	tst.l	a0
	jbeq	5$

	jbra	2$
1$:	move.b	(a0)+,(a1)
	tst.b	(a1)
2$:	dbra	d0,1$
3$:	rts

4$:	st.b	(a1)
	tst.b	(a1)
5$:	dbra	d0,4$
	rts


#endif /* CONF_WITH_VAMPIRE_SPI */
