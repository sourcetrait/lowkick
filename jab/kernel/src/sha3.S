.include "riscv.inc"
.include "jab.inc"

# SHA3-256, which is Keccak with a rate of 136 bytes and a capacity of
# 64. The state is 25 lanes of 64 bits, which RV64 holds one to a
# register; a block is exclusive-ored into the first 17 of them and the
# permutation is run; the last block carries the padding, 0x06 where the
# message ends and 0x80 in the last byte, both of which land in the same
# byte for a block that is one short. The digest is the first four lanes,
# and since a lane is written out little-endian, those four lanes are
# the digest exactly as anything else computes it - which is why the
# call hands them back in a0 to a3 rather than into a buffer.
#
# The permutation itself is the five steps of the specification, kept as
# loops over two small tables rather than unrolled: pi says where each
# lane goes and rho how far it turns, and between them they are the only
# part that is not arithmetic on neighbours.

.set SHA3_LANES, 25
.set SHA3_RATE, 136
.set SHA3_ROUNDS, 24
.set SHA3_PAD, 0x06
.set SHA3_LAST, 0x80

.section .text

# sys_checksum (jab.checksum): a0 is an address in the program's window
# and a1 how many bytes. a0 to a3 become the digest, the four lanes in
# the order a program would write them out.
.global sys_checksum
sys_checksum:
    ld a0, 80(sp)
    ld a1, 88(sp)
    call buffer_bounds
    ld a0, 80(sp)
    ld a1, 88(sp)
    call sha3_256
    la t0, sha3_a
    ld t1, 0(t0)
    sd t1, 80(sp)
    ld t1, 8(t0)
    sd t1, 88(sp)
    ld t1, 16(t0)
    sd t1, 96(sp)
    ld t1, 24(t0)
    sd t1, 104(sp)
    j trap_return

# sha3_256: a0 is the bytes and a1 how many. The digest is left in the
# first four lanes of the state.
.global sha3_256
sha3_256:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    # a fresh state
    la t0, sha3_a
    li t1, 0
1:
    li t2, SHA3_LANES
    bgeu t1, t2, 2f
    slli t3, t1, 3
    add t3, t3, t0
    sd zero, 0(t3)
    addi t1, t1, 1
    j 1b
2:
    sd zero, 16(sp)             # how far into the message
3:
    ld t0, 8(sp)
    ld t1, 16(sp)
    sub t2, t0, t1
    li t3, SHA3_RATE
    bltu t2, t3, 5f
    # a whole block, straight out of the message
    ld t4, 0(sp)
    add a0, t4, t1
    call sha3_absorb
    call keccak_f
    ld t1, 16(sp)
    li t3, SHA3_RATE
    add t1, t1, t3
    sd t1, 16(sp)
    j 3b
5:
    # the last block: what is left, then the padding
    la a0, sha3_block
    li a1, SHA3_RATE
    call zero_bytes
    ld t0, 8(sp)
    ld t1, 16(sp)
    sub t2, t0, t1              # how many are left
    la a0, sha3_block
    ld t3, 0(sp)
    add a1, t3, t1
    mv a2, t2
    sd t2, 16(sp)
    call copy_bytes
    la t0, sha3_block
    ld t2, 16(sp)
    add t1, t0, t2
    li t3, SHA3_PAD
    lbu t4, 0(t1)
    or t3, t3, t4
    sb t3, 0(t1)
    addi t1, t0, SHA3_RATE - 1
    lbu t3, 0(t1)
    li t4, SHA3_LAST
    or t3, t3, t4
    sb t3, 0(t1)
    la a0, sha3_block
    call sha3_absorb
    call keccak_f
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# sha3_absorb: a0 is SHA3_RATE bytes; they are exclusive-ored into the
# first lanes of the state, each lane read little-endian a byte at a
# time so nothing depends on how the message happens to be aligned.
sha3_absorb:
    li t0, 0                    # the lane
1:
    li t1, SHA3_RATE / 8
    bgeu t0, t1, 9f
    slli t1, t0, 3
    add t1, t1, a0              # the eight bytes
    li t2, 0                    # the lane's value
    li t3, 0                    # the byte
2:
    li t4, 8
    bgeu t3, t4, 3f
    add t4, t1, t3
    lbu t4, 0(t4)
    slli t5, t3, 3
    sll t4, t4, t5
    or t2, t2, t4
    addi t3, t3, 1
    j 2b
3:
    la t4, sha3_a
    slli t5, t0, 3
    add t4, t4, t5
    ld t5, 0(t4)
    xor t5, t5, t2
    sd t5, 0(t4)
    addi t0, t0, 1
    j 1b
9:
    ret

# keccak_f: the permutation, SHA3_ROUNDS of theta, rho with pi, chi and
# iota. Nothing here calls anything, so the t registers hold throughout.
.global keccak_f
keccak_f:
    li t6, 0                    # the round
1:
    # theta: each column folded to one lane, then every lane in a column
    # turned by its neighbours
    la t0, sha3_a
    la t1, sha3_c
    li t2, 0
2:
    li t3, 5
    bgeu t2, t3, 3f
    slli t3, t2, 3
    add t3, t3, t0
    ld t4, 0(t3)
    ld t5, 40(t3)
    xor t4, t4, t5
    ld t5, 80(t3)
    xor t4, t4, t5
    ld t5, 120(t3)
    xor t4, t4, t5
    ld t5, 160(t3)
    xor t4, t4, t5
    slli t5, t2, 3
    add t5, t5, t1
    sd t4, 0(t5)
    addi t2, t2, 1
    j 2b
3:
    li t2, 0
4:
    li t3, 5
    bgeu t2, t3, 6f
    # d = c[x - 1] ^ rotl(c[x + 1], 1)
    la t3, sha3_prev
    add t3, t3, t2
    lbu t3, 0(t3)
    slli t3, t3, 3
    add t3, t3, t1
    ld t3, 0(t3)
    la t4, sha3_next
    add t4, t4, t2
    lbu t4, 0(t4)
    slli t4, t4, 3
    add t4, t4, t1
    ld t4, 0(t4)
    slli t5, t4, 1
    srli t4, t4, 63
    or t4, t4, t5
    xor t3, t3, t4              # d
    li t4, 0
5:
    li t5, 5
    bgeu t4, t5, 55f
    li t5, 5
    mul t5, t4, t5
    add t5, t5, t2
    slli t5, t5, 3
    add t5, t5, t0
    ld a0, 0(t5)
    xor a0, a0, t3
    sd a0, 0(t5)
    addi t4, t4, 1
    j 5b
55:
    addi t2, t2, 1
    j 4b
6:
    # rho and pi together: every lane turned and moved at once
    la t1, sha3_b
    li t2, 0
7:
    li t3, SHA3_LANES
    bgeu t2, t3, 8f
    slli t3, t2, 3
    add t3, t3, t0
    ld t4, 0(t3)                # the lane
    la t3, sha3_rho
    add t3, t3, t2
    lbu t3, 0(t3)               # how far it turns
    sll t5, t4, t3
    li a0, 64
    sub a0, a0, t3
    srl t4, t4, a0
    or t4, t4, t5
    la t3, sha3_pi
    add t3, t3, t2
    lbu t3, 0(t3)               # where it goes
    slli t3, t3, 3
    add t3, t3, t1
    sd t4, 0(t3)
    addi t2, t2, 1
    j 7b
8:
    # chi: each lane against the two after it in its row
    li t2, 0                    # the row
81:
    li t3, 5
    bgeu t2, t3, 9f
    li t3, 0                    # the column
82:
    li t4, 5
    bgeu t3, t4, 88f
    li t4, 5
    mul t4, t2, t4
    add t5, t4, t3              # this lane
    slli a0, t5, 3
    add a0, a0, t1
    ld a1, 0(a0)
    la a0, sha3_next
    add a0, a0, t3
    lbu a0, 0(a0)
    add a0, a0, t4
    slli a0, a0, 3
    add a0, a0, t1
    ld a2, 0(a0)
    la a0, sha3_next2
    add a0, a0, t3
    lbu a0, 0(a0)
    add a0, a0, t4
    slli a0, a0, 3
    add a0, a0, t1
    ld a3, 0(a0)
    not a2, a2
    and a2, a2, a3
    xor a1, a1, a2
    slli a0, t5, 3
    add a0, a0, t0
    sd a1, 0(a0)
    addi t3, t3, 1
    j 82b
88:
    addi t2, t2, 1
    j 81b
9:
    # iota: this round's constant into the first lane
    la t1, sha3_rc
    slli t2, t6, 3
    add t1, t1, t2
    ld t1, 0(t1)
    ld t2, 0(t0)
    xor t2, t2, t1
    sd t2, 0(t0)
    addi t6, t6, 1
    li t1, SHA3_ROUNDS
    bltu t6, t1, 1b
    ret

.section .rodata
.balign 8
# where each lane goes, and how far it turns, on its way there
sha3_pi:
    .byte 0, 10, 20, 5, 15, 16, 1, 11, 21, 6, 7, 17, 2, 12, 22
    .byte 23, 8, 18, 3, 13, 14, 24, 9, 19, 4
sha3_rho:
    .byte 0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39
    .byte 41, 45, 15, 21, 8, 18, 2, 61, 56, 14
sha3_next:
    .byte 1, 2, 3, 4, 0
sha3_next2:
    .byte 2, 3, 4, 0, 1
sha3_prev:
    .byte 4, 0, 1, 2, 3
.balign 8
sha3_rc:
    .quad 0x0000000000000001, 0x0000000000008082
    .quad 0x800000000000808a, 0x8000000080008000
    .quad 0x000000000000808b, 0x0000000080000001
    .quad 0x8000000080008081, 0x8000000000008009
    .quad 0x000000000000008a, 0x0000000000000088
    .quad 0x0000000080008009, 0x000000008000000a
    .quad 0x000000008000808b, 0x800000000000008b
    .quad 0x8000000000008089, 0x8000000000008003
    .quad 0x8000000000008002, 0x8000000000000080
    .quad 0x000000000000800a, 0x800000008000000a
    .quad 0x8000000080008081, 0x8000000000008080
    .quad 0x0000000080000001, 0x8000000080008008

.section .bss
.balign 8
.global sha3_a
sha3_a:
    .skip SHA3_LANES * 8
sha3_b:
    .skip SHA3_LANES * 8
sha3_c:
    .skip 5 * 8
sha3_block:
    .skip SHA3_RATE
