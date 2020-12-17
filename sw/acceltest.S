/* Base address of the GPIO controller used for DIP switches and LED */
#ifndef GPIO_BASE
#define GPIO_BASE 0x80001010
#endif

#define RAM_INIT_DONE 0x8000100A
#define UART_BASE     0x80002000

/* Base address of the SPI controller used to communicate with the Flash */
#ifndef SPI_BASE
#define SPI_BASE 0x80001080
#endif

/* Base address of the GPIO controller used to blink LED */
#ifndef GPIO_BASE
#define GPIO_BASE 0x80001010
#endif


#define REG_BRDL (4*0x00) /* Baud rate divisor (LSB)        */
#define REG_IER (4*0x01)  /* Interrupt enable reg.          */
#define REG_FCR (4*0x02)  /* FIFO control reg.              */
#define REG_LCR (4*0x03)  /* Line control reg.              */
#define REG_LSR (4*0x05)  /* Line status reg.               */
#define LCR_CS8 0x03   /* 8 bits data size */
#define LCR_1_STB 0x00 /* 1 stop bit */
#define LCR_PDIS 0x00  /* parity disable */

#define LSR_THRE 0x20
#define FCR_FIFO 0x01    /* enable XMIT and RCVR FIFO */
#define FCR_RCVRCLR 0x02 /* clear RCVR FIFO */
#define FCR_XMITCLR 0x04 /* clear XMIT FIFO */
#define FCR_MODE0 0x00 /* set receiver in mode 0 */
#define FCR_MODE1 0x08 /* set receiver in mode 1 */
#define FCR_FIFO_8 0x80  /* 8 bytes in RCVR FIFO */

#define SPI_SPCR 0x00
#define SPI_SPSR 0x08
#define SPI_SPDR 0x10
#define SPI_SPER 0x18
#define SPI_SPSS 0x20

#define SPI_SPSS_INIT 0x1
#define SPI_SPSR_RX_CHECK 0x01 /* Check bit 0 is cleared, fifo !empty*/

/* Flash needs 300 us to warm up from power-on. In practice, this is only an
   issue in simulations as FPGA boot is far longer than 300 us
*/
#ifndef INIT_DELAY
#define INIT_DELAY 700
#endif



	/* Registers used
	a4 = UART base
	a5 = String to print
	*/

.globl _start
.globl boot_fail
_start:
	jal	uart_init

	la	a5, boot_msg
	jal	uart_writestr

	/* Wait until RAM initialization is done */
	li	t1, RAM_INIT_DONE
1:	lbu	t2, 0(t1)
	beqz	t2, 1b
	la	a5, ram_ok
	jal	uart_writestr

#if INIT_DELAY
    li t1, INIT_DELAY
    and t2, zero, zero
1:	addi t2,t2,1
    bne t1, t2, 1b
#endif

    /* Load SPI base address to gp */
    li gp, SPI_BASE

spi_init:
    li    a1,0x12
    /* Clear slave selects */
    sb	zero, SPI_SPSS(gp)
    fence

    /* Set clock divider to 64 (arbitrarily chosen value)
    and enable controller */
    addi	t1, zero, 0x40 | 0x01
    sb	t1, SPI_SPCR(gp)
    fence

    /* Second Part of Speed Divider*/
    addi        t1, zero, 0x01
    sb  t1, SPI_SPER(gp)
    fence

    /* Set appropriate slave select */
    addi	t1, zero, 1
    sb	t1, SPI_SPSS(gp)
    fence

    li	a0, 0x0b
    jal	spi_xfer

    li  a0, 0x00
    jal spi_xfer

    jal spi_xfer

    srli t0,a1,4
    andi t0,t0,0x0f
    addi t0,t0,48
    jal  putchar2

    andi t0,a1,0x0f
    addi t0,t0,48
    jal  putchar2


	/* Spin here on boot failures */
boot_fail:	j boot_fail


spi_xfer:
    /* Loop four times */

spi_xfer_loop:
    /* Send data in a0[7:0] */
    sb	a0, SPI_SPDR(gp)
    fence

spi_xfer_poll:
    /* Wait for data in RX FIFO */
    lbu	t1, SPI_SPSR(gp)
    fence
    andi	t1, t1, SPI_SPSR_RX_CHECK
    bnez	t1, spi_xfer_poll

    lbu	a1, SPI_SPDR(gp)

    ret

uart_init:
	/* Init UART */
	li	a4, UART_BASE

	/* Set DLAB bit in LCR */
	li	t3, 0x80
	sb	t3, REG_LCR(a4)

	/* Set divisor regs */
	li	t4, 27
	sb	t4, REG_BRDL(a4)

	/* 8 data bits, 1 stop bit, no parity, clear DLAB */
	li	t3, LCR_CS8 | LCR_1_STB | LCR_PDIS
	sb	t3, REG_LCR(a4)

	li	t3, FCR_FIFO | FCR_MODE0 | FCR_FIFO_8 | FCR_RCVRCLR | FCR_XMITCLR
	sb	t3, REG_FCR(a4)

	/* disable interrupts  */
	sb	zero, REG_IER(a4)
	ret

uart_writestr: /* Write string at a5 */

	/* Load first byte */
	lb t0, 0(a5)

nextchar:
	/* Write to console and load next char until we get \0 */
putchar:
	/* Check for space in UART FIFO */
	lb	t6, REG_LSR(a4)
	andi	t6, t6, LSR_THRE
	beqz	t6, putchar

	/* Write byte */
	sb	t0, 0(a4)

	addi a5, a5, 1
	lb t0, 0(a5)
	bne t0, zero, nextchar

	ret

putchar2:
    /* Check for space in UART FIFO */
    lb	t6, REG_LSR(a4)
    andi	t6, t6, LSR_THRE
    beqz	t6, putchar2

    /* Write byte */
    sb	t0, 0(a4)

    ret

boot_msg:
	.string "Accel Test...\r\n"
ram_ok:
	.string "RAM OK\r\n"
