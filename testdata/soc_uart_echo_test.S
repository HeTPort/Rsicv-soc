    .section .text
    .globl _start

    .equ UART_TXDATA,  0x10000000
    .equ UART_STATUS,  0x10000004
    .equ UART_RXDATA,  0x10000008
    .equ UART_RXERROR, 0x1000000C
    .equ TX_READY, 0x1
    .equ TX_BUSY,  0x2
    .equ RX_VALID, 0x4
    .equ TOHOST, 0x8000FFFC

_start:
    li      s0, 16

receive_next:
    li      t0, UART_STATUS
1:  lw      t1, 0(t0)
    andi    t1, t1, RX_VALID
    beqz    t1, 1b

    li      t0, UART_RXDATA
    lw      a0, 0(t0)

    li      t0, UART_STATUS
2:  lw      t1, 0(t0)
    andi    t1, t1, TX_READY
    beqz    t1, 2b
    li      t0, UART_TXDATA
    sw      a0, 0(t0)

    addi    s0, s0, -1
    bnez    s0, receive_next

    # The test is successful only if no asynchronous input was lost or framed
    # incorrectly and the final echoed stop bit has left the pin.
    li      t0, UART_RXERROR
    lw      t1, 0(t0)
    bnez    t1, fail
    li      t0, UART_STATUS
3:  lw      t1, 0(t0)
    andi    t1, t1, TX_BUSY
    bnez    t1, 3b

    li      t1, 1
    j       report
fail:
    li      t1, 2
report:
    li      t0, TOHOST
    sw      t1, 0(t0)
4:  j       4b
