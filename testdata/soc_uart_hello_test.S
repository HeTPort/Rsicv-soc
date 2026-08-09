    .section .text
    .globl _start

    .equ UART_TXDATA, 0x10000000
    .equ UART_STATUS, 0x10000004
    .equ UART_TX_READY, 0x1
    .equ UART_TX_BUSY,  0x2
    .equ TOHOST, 0x8000FFFC

_start:
    li      a0, 'H'
    jal     ra, uart_putc
    li      a0, 'e'
    jal     ra, uart_putc
    li      a0, 'l'
    jal     ra, uart_putc
    li      a0, 'l'
    jal     ra, uart_putc
    li      a0, 'o'
    jal     ra, uart_putc
    li      a0, ','
    jal     ra, uart_putc
    li      a0, ' '
    jal     ra, uart_putc
    li      a0, 'U'
    jal     ra, uart_putc
    li      a0, 'A'
    jal     ra, uart_putc
    li      a0, 'R'
    jal     ra, uart_putc
    li      a0, 'T'
    jal     ra, uart_putc
    li      a0, '!'
    jal     ra, uart_putc
    li      a0, 13
    jal     ra, uart_putc
    li      a0, 10
    jal     ra, uart_putc

    # Do not report PASS until the last stop bit has left the serial pin.
    li      t0, UART_STATUS
wait_idle:
    lw      t1, 0(t0)
    andi    t1, t1, UART_TX_BUSY
    bnez    t1, wait_idle

    li      t0, TOHOST
    li      t1, 1
    sw      t1, 0(t0)
1:  j       1b

# a0 = byte. Polling is the software flow-control contract; the bus target's
# backpressure remains a second, lossless safety layer.
uart_putc:
    li      t0, UART_STATUS
1:  lw      t1, 0(t0)
    andi    t1, t1, UART_TX_READY
    beqz    t1, 1b
    li      t0, UART_TXDATA
    sw      a0, 0(t0)
    ret
