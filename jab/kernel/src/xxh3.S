.include "riscv.inc"
.include "jab.inc"

# XXH3-64, the default fast hash. TheUser's reason for choosing it over
# the far smaller XXH64 is that it matches what the estate hashes with
# everywhere else, and he took its cost knowingly.
#
# It is four algorithms behind one name, chosen by length, over a fixed
# 192-byte secret: up to 16 bytes it is a keyed mix and an avalanche;
# to 128 it is pairs of 16-byte mixes working inward from both ends; to
# 240 it adds a second pass; and beyond that it runs eight accumulators
# over 64-byte stripes, scrambling them every sixteen, then folds them
# down. The seed is always zero here, which removes the seed arithmetic
# from every branch: what the reference adds to or subtracts from a
# secret word is simply that word.
#
# Every constant below, the secret included, is copied from the
# reference at a pinned tag rather than written from memory, because one
# wrong byte is a hash that is wrong everywhere and says nothing about
# where. Reads are byte-wise little-endian so nothing depends on how the
# program's buffer happens to sit, and everything that must outlive a
# call is in bss or on the stack rather than in a t register.

.set XX_STRIPE, 64
.set XX_ACCS, 8
.set XX_SECRET, 192
.set XX_CONSUME, 8
.set XX_STRIPES_PER_BLOCK, ((XX_SECRET - XX_STRIPE) / XX_CONSUME)
.set XX_BLOCK, (XX_STRIPE * XX_STRIPES_PER_BLOCK)
.set XX_MERGE_START, 11
.set XX_LASTACC_START, 7
.set XX_SECRET_SIZE_MIN, 136
.set XX_MIDSIZE_START, 3
.set XX_MIDSIZE_LAST, 17

.section .text

# sys_hash (jab.hash): a0 is an address in the program's window and a1
# how many bytes. a0 becomes the hash, which is one register wide.
.global sys_hash
sys_hash:
    ld a0, 80(sp)
    ld a1, 88(sp)
    call buffer_bounds
    ld a0, 80(sp)
    ld a1, 88(sp)
    call xxh3_64
    sd a0, 80(sp)
    j trap_return

# xxh3_64: a0 is the bytes and a1 how many; a0 becomes the hash.
.global xxh3_64
xxh3_64:
    addi sp, sp, -16
    sd ra, 8(sp)
    li t0, 16
    bgtu a1, t0, 1f
    call xx_short
    j 9f
1:
    li t0, 128
    bgtu a1, t0, 2f
    call xx_mid
    j 9f
2:
    li t0, 240
    bgtu a1, t0, 3f
    call xx_midlarge
    j 9f
3:
    call xx_long
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# xx_short: up to and including 16 bytes, in four cases of its own.
xx_short:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    beqz a1, 8f
    li t0, 4
    bgeu a1, t0, 4f
    # one to three bytes: the first, the middle and the last, with the
    # length itself, packed into a word
    ld t0, 0(sp)
    ld t1, 8(sp)
    lbu t2, 0(t0)               # c1
    srli t3, t1, 1
    add t3, t0, t3
    lbu t3, 0(t3)               # c2
    add t4, t0, t1
    lbu t4, -1(t4)              # c3
    slli t2, t2, 16
    slli t3, t3, 24
    slli t5, t1, 8
    or t2, t2, t3
    or t2, t2, t4
    or t2, t2, t5
    li t3, 0xffffffff
    and t2, t2, t3
    sd t2, 16(sp)
    la a0, xx_secret
    call xx_le32
    mv t5, a0
    la a0, xx_secret
    addi a0, a0, 4
    call xx_le32
    xor t5, t5, a0
    li t3, 0xffffffff
    and t5, t5, t3
    ld t2, 16(sp)
    xor a0, t2, t5
    call xx64_avalanche
    j 9f
4:
    li t0, 8
    bgtu a1, t0, 5f
    # four to eight: the first word and the last, joined
    ld a0, 0(sp)
    call xx_le32
    sd a0, 16(sp)
    ld t0, 0(sp)
    ld t1, 8(sp)
    add a0, t0, t1
    addi a0, a0, -4
    call xx_le32
    ld t1, 16(sp)
    slli t1, t1, 32
    add t2, a0, t1
    sd t2, 16(sp)
    la a0, xx_secret
    addi a0, a0, 8
    call xx_le64
    sd a0, 0(sp)
    la a0, xx_secret
    addi a0, a0, 16
    call xx_le64
    ld t0, 0(sp)
    xor t0, t0, a0              # the bitflip
    ld t2, 16(sp)
    xor a0, t2, t0
    ld a1, 8(sp)
    call xx_rrmxmx
    j 9f
5:
    # nine to sixteen: the first eight and the last eight
    la a0, xx_secret
    addi a0, a0, 24
    call xx_le64
    sd a0, 16(sp)
    la a0, xx_secret
    addi a0, a0, 32
    call xx_le64
    ld t0, 16(sp)
    xor t0, t0, a0
    sd t0, 16(sp)               # bitflip1
    la a0, xx_secret
    addi a0, a0, 40
    call xx_le64
    mv t1, a0
    sd t1, 24(sp)
    la a0, xx_secret
    addi a0, a0, 48
    call xx_le64
    ld t1, 24(sp)
    xor t1, t1, a0
    sd t1, 24(sp)               # bitflip2
    ld a0, 0(sp)
    call xx_le64
    ld t0, 16(sp)
    xor t0, t0, a0
    la t2, xx_lo
    sd t0, 0(t2)                # input_lo
    ld t0, 0(sp)
    ld t1, 8(sp)
    add a0, t0, t1
    addi a0, a0, -8
    call xx_le64
    ld t1, 24(sp)
    xor t1, t1, a0
    la t2, xx_hi
    sd t1, 0(t2)                # input_hi
    la t2, xx_lo
    ld a0, 0(t2)
    la t2, xx_hi
    ld a1, 0(t2)
    call xx_mul128_fold
    mv t3, a0
    la t2, xx_lo
    ld a0, 0(t2)
    sd t3, 24(sp)
    call xx_bswap64
    ld t3, 24(sp)
    add t3, t3, a0
    la t2, xx_hi
    ld t2, 0(t2)
    add t3, t3, t2
    ld t1, 8(sp)
    add a0, t3, t1
    call xx_avalanche
    j 9f
8:
    # nothing at all
    la a0, xx_secret
    addi a0, a0, 56
    call xx_le64
    sd a0, 16(sp)
    la a0, xx_secret
    addi a0, a0, 64
    call xx_le64
    ld t0, 16(sp)
    xor a0, t0, a0
    call xx64_avalanche
9:
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# xx_mid: seventeen to a hundred and twenty-eight bytes, as pairs of
# mixes working inward from both ends.
xx_mid:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    la t0, xx_prime64_1
    ld t0, 0(t0)
    mul t1, a1, t0
    sd t1, 16(sp)               # the accumulator
    addi t2, a1, -1
    li t3, 32
    divu t2, t2, t3
    sd t2, 24(sp)               # the pair being done
1:
    ld t2, 24(sp)
    slli t3, t2, 4
    ld t0, 0(sp)
    add a0, t0, t3              # input + 16 i
    slli t3, t2, 5
    la a1, xx_secret
    add a1, a1, t3              # secret + 32 i
    call xx_mix16
    ld t1, 16(sp)
    add t1, t1, a0
    sd t1, 16(sp)
    ld t2, 24(sp)
    addi t3, t2, 1
    slli t3, t3, 4
    ld t0, 0(sp)
    ld t1, 8(sp)
    add t0, t0, t1
    sub a0, t0, t3              # input + len - 16 (i + 1)
    slli t3, t2, 5
    la a1, xx_secret
    add a1, a1, t3
    addi a1, a1, 16             # secret + 32 i + 16
    call xx_mix16
    ld t1, 16(sp)
    add t1, t1, a0
    sd t1, 16(sp)
    ld t2, 24(sp)
    beqz t2, 2f
    addi t2, t2, -1
    sd t2, 24(sp)
    j 1b
2:
    ld a0, 16(sp)
    call xx_avalanche
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# xx_midlarge: a hundred and twenty-nine to two hundred and forty, as
# eight mixes, then the rest against a shifted secret, the two halves
# avalanched apart and added.
xx_midlarge:
    addi sp, sp, -64
    sd ra, 56(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    la t0, xx_prime64_1
    ld t0, 0(t0)
    mul t1, a1, t0
    sd t1, 16(sp)               # acc
    li t2, 16
    divu t2, a1, t2
    sd t2, 24(sp)               # how many rounds there are
    sd zero, 32(sp)             # the round
1:
    ld t2, 32(sp)
    li t3, 8
    bgeu t2, t3, 2f
    slli t3, t2, 4
    ld t0, 0(sp)
    add a0, t0, t3
    la a1, xx_secret
    add a1, a1, t3
    call xx_mix16
    ld t1, 16(sp)
    add t1, t1, a0
    sd t1, 16(sp)
    ld t2, 32(sp)
    addi t2, t2, 1
    sd t2, 32(sp)
    j 1b
2:
    # the last sixteen bytes, against the end of the smallest secret
    ld t0, 0(sp)
    ld t1, 8(sp)
    add a0, t0, t1
    addi a0, a0, -16
    la a1, xx_secret
    addi a1, a1, XX_SECRET_SIZE_MIN - XX_MIDSIZE_LAST
    call xx_mix16
    sd a0, 40(sp)               # acc_end
    ld a0, 16(sp)
    call xx_avalanche
    sd a0, 16(sp)
3:
    ld t2, 32(sp)
    ld t3, 24(sp)
    bgeu t2, t3, 4f
    slli t3, t2, 4
    ld t0, 0(sp)
    add a0, t0, t3
    addi t3, t2, -8
    slli t3, t3, 4
    la a1, xx_secret
    add a1, a1, t3
    addi a1, a1, XX_MIDSIZE_START
    call xx_mix16
    ld t1, 40(sp)
    add t1, t1, a0
    sd t1, 40(sp)
    ld t2, 32(sp)
    addi t2, t2, 1
    sd t2, 32(sp)
    j 3b
4:
    ld t0, 16(sp)
    ld t1, 40(sp)
    add a0, t0, t1
    call xx_avalanche
    ld ra, 56(sp)
    addi sp, sp, 64
    ret

# xx_long: past two hundred and forty, over eight accumulators.
xx_long:
    addi sp, sp, -64
    sd ra, 56(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    # the accumulators start at their primes
    la t0, xx_acc
    la t1, xx_init
    li t2, 0
1:
    li t3, XX_ACCS
    bgeu t2, t3, 2f
    slli t3, t2, 3
    add t4, t1, t3
    ld t4, 0(t4)
    add t3, t0, t3
    sd t4, 0(t3)
    addi t2, t2, 1
    j 1b
2:
    # whole blocks of sixteen stripes, scrambled after each
    ld t1, 8(sp)
    addi t1, t1, -1
    li t2, XX_BLOCK
    divu t1, t1, t2
    sd t1, 16(sp)               # how many blocks
    sd zero, 24(sp)             # the block
3:
    ld t1, 24(sp)
    ld t2, 16(sp)
    bgeu t1, t2, 4f
    li t3, XX_BLOCK
    mul t3, t1, t3
    ld t0, 0(sp)
    add a0, t0, t3
    la a1, xx_secret
    li a2, XX_STRIPES_PER_BLOCK
    call xx_accumulate
    la a0, xx_secret
    addi a0, a0, XX_SECRET - XX_STRIPE
    call xx_scramble
    ld t1, 24(sp)
    addi t1, t1, 1
    sd t1, 24(sp)
    j 3b
4:
    # then the stripes left over, and the last stripe of all
    ld t1, 8(sp)
    addi t1, t1, -1
    ld t2, 24(sp)
    li t3, XX_BLOCK
    mul t2, t2, t3
    sub t1, t1, t2
    li t3, XX_STRIPE
    divu t1, t1, t3             # how many stripes are left
    ld t0, 0(sp)
    add a0, t0, t2
    la a1, xx_secret
    mv a2, t1
    call xx_accumulate
    ld t0, 0(sp)
    ld t1, 8(sp)
    add a0, t0, t1
    addi a0, a0, -XX_STRIPE
    la a1, xx_secret
    addi a1, a1, XX_SECRET - XX_STRIPE - XX_LASTACC_START
    call xx_accumulate_512
    # fold the accumulators down
    la t0, xx_prime64_1
    ld t0, 0(t0)
    ld t1, 8(sp)
    mul a0, t1, t0
    call xx_merge
    ld ra, 56(sp)
    addi sp, sp, 64
    ret

# xx_accumulate: a0 is the input, a1 the secret, a2 how many stripes.
xx_accumulate:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    sd a2, 16(sp)
    li t0, 0
1:
    ld t1, 16(sp)
    bgeu t0, t1, 9f
    la t2, xx_stripe_n
    sd t0, 0(t2)
    li t1, XX_STRIPE
    mul t1, t0, t1
    ld t2, 0(sp)
    add a0, t2, t1
    li t1, XX_CONSUME
    mul t1, t0, t1
    ld t2, 8(sp)
    add a1, t2, t1
    call xx_accumulate_512
    la t2, xx_stripe_n
    ld t0, 0(t2)
    addi t0, t0, 1
    j 1b
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# xx_accumulate_512: one 64-byte stripe at a0 against the secret at a1.
xx_accumulate_512:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    sd zero, 16(sp)             # the lane
1:
    ld t0, 16(sp)
    li t1, XX_ACCS
    bgeu t0, t1, 9f
    slli t1, t0, 3
    ld t2, 0(sp)
    add a0, t2, t1
    call xx_le64
    la t2, xx_data
    sd a0, 0(t2)                # data_val
    ld t0, 16(sp)
    slli t1, t0, 3
    ld t2, 8(sp)
    add a0, t2, t1
    call xx_le64
    la t2, xx_data
    ld t1, 0(t2)
    xor t2, t1, a0              # data_key
    ld t0, 16(sp)
    # the neighbouring lane takes the value as it is
    xori t3, t0, 1
    slli t3, t3, 3
    la t4, xx_acc
    add t3, t4, t3
    ld t5, 0(t3)
    add t5, t5, t1
    sd t5, 0(t3)
    # and this one the product of the key's halves
    li t3, 0xffffffff
    and t4, t2, t3
    srli t5, t2, 32
    mul t4, t4, t5
    slli t3, t0, 3
    la t5, xx_acc
    add t3, t5, t3
    ld t5, 0(t3)
    add t5, t5, t4
    sd t5, 0(t3)
    addi t0, t0, 1
    sd t0, 16(sp)
    j 1b
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# xx_scramble: the accumulators against the secret at a0.
xx_scramble:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd zero, 8(sp)
1:
    ld t0, 8(sp)
    li t1, XX_ACCS
    bgeu t0, t1, 9f
    slli t1, t0, 3
    ld t2, 0(sp)
    add a0, t2, t1
    call xx_le64
    ld t0, 8(sp)
    slli t1, t0, 3
    la t2, xx_acc
    add t1, t2, t1
    ld t2, 0(t1)
    srli t3, t2, 47
    xor t2, t2, t3
    xor t2, t2, a0
    la t3, xx_prime32_1
    ld t3, 0(t3)
    mul t2, t2, t3
    sd t2, 0(t1)
    addi t0, t0, 1
    sd t0, 8(sp)
    j 1b
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# xx_merge: a0 is where the fold starts; a0 becomes the hash.
xx_merge:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd zero, 8(sp)
1:
    ld t0, 8(sp)
    li t1, 4
    bgeu t0, t1, 9f
    slli t1, t0, 4
    la t2, xx_secret
    add t2, t2, t1
    addi t2, t2, XX_MERGE_START
    sd t2, 16(sp)
    mv a0, t2
    call xx_le64
    ld t0, 8(sp)                # a call keeps no t register
    slli t1, t0, 4
    la t2, xx_acc
    add t2, t2, t1
    ld t2, 0(t2)
    xor t3, t2, a0
    la t2, xx_lo
    sd t3, 0(t2)
    ld t2, 16(sp)
    addi a0, t2, 8
    call xx_le64
    ld t0, 8(sp)
    slli t1, t0, 4
    la t2, xx_acc
    add t2, t2, t1
    ld t2, 8(t2)
    xor a1, t2, a0
    la t2, xx_lo
    ld a0, 0(t2)
    call xx_mul128_fold
    ld t1, 0(sp)
    add t1, t1, a0
    sd t1, 0(sp)
    ld t0, 8(sp)
    addi t0, t0, 1
    sd t0, 8(sp)
    j 1b
9:
    ld a0, 0(sp)
    call xx_avalanche
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# xx_mix16: sixteen bytes at a0 against sixteen of the secret at a1.
xx_mix16:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    call xx_le64
    la t0, xx_lo
    sd a0, 0(t0)
    ld a0, 8(sp)
    call xx_le64
    la t0, xx_lo
    ld t1, 0(t0)
    xor t1, t1, a0
    sd t1, 0(t0)
    ld a0, 0(sp)
    addi a0, a0, 8
    call xx_le64
    la t0, xx_hi
    sd a0, 0(t0)
    ld a0, 8(sp)
    addi a0, a0, 8
    call xx_le64
    la t0, xx_hi
    ld t1, 0(t0)
    xor t1, t1, a0
    mv a1, t1
    la t0, xx_lo
    ld a0, 0(t0)
    call xx_mul128_fold
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# xx_mul128_fold: the two halves of a0 times a1, folded together.
xx_mul128_fold:
    mul t0, a0, a1
    mulhu t1, a0, a1
    xor a0, t0, t1
    ret

# xx_avalanche and xx64_avalanche: the two finishers.
xx_avalanche:
    srli t0, a0, 37
    xor a0, a0, t0
    la t1, xx_prime_mx1
    ld t1, 0(t1)
    mul a0, a0, t1
    srli t0, a0, 32
    xor a0, a0, t0
    ret

xx64_avalanche:
    srli t0, a0, 33
    xor a0, a0, t0
    la t1, xx_prime64_2
    ld t1, 0(t1)
    mul a0, a0, t1
    srli t0, a0, 29
    xor a0, a0, t0
    la t1, xx_prime64_3
    ld t1, 0(t1)
    mul a0, a0, t1
    srli t0, a0, 32
    xor a0, a0, t0
    ret

# xx_rrmxmx: a0 is the value and a1 the length.
xx_rrmxmx:
    slli t0, a0, 49
    srli t1, a0, 15
    or t0, t0, t1               # turned by 49
    slli t2, a0, 24
    srli t3, a0, 40
    or t2, t2, t3               # and by 24
    xor t0, t0, t2
    xor a0, a0, t0
    la t1, xx_prime_mx2
    ld t1, 0(t1)
    mul a0, a0, t1
    srli t0, a0, 35
    add t0, t0, a1
    xor a0, a0, t0
    mul a0, a0, t1
    srli t0, a0, 28
    xor a0, a0, t0
    ret

# xx_bswap64: a0 with its bytes the other way round.
xx_bswap64:
    li t0, 0
    li t1, 0
1:
    li t2, 8
    bgeu t1, t2, 2f
    slli t0, t0, 8
    andi t3, a0, 0xff
    or t0, t0, t3
    srli a0, a0, 8
    addi t1, t1, 1
    j 1b
2:
    mv a0, t0
    ret

# xx_le64 and xx_le32: a little-endian value at a0, read a byte at a
# time so nothing depends on how the buffer is aligned.
xx_le64:
    li t0, 0
    li t1, 0
1:
    li t2, 8
    bgeu t1, t2, 2f
    add t3, a0, t1
    lbu t3, 0(t3)
    slli t4, t1, 3
    sll t3, t3, t4
    or t0, t0, t3
    addi t1, t1, 1
    j 1b
2:
    mv a0, t0
    ret

xx_le32:
    lbu t0, 0(a0)
    lbu t1, 1(a0)
    slli t1, t1, 8
    or t0, t0, t1
    lbu t1, 2(a0)
    slli t1, t1, 16
    or t0, t0, t1
    lbu t1, 3(a0)
    slli t1, t1, 24
    or a0, t0, t1
    ret

.section .rodata
.balign 8
xx_prime64_1:
    .quad 0x9e3779b185ebca87
xx_prime64_2:
    .quad 0xc2b2ae3d27d4eb4f
xx_prime64_3:
    .quad 0x165667b19e3779f9
xx_prime64_4:
    .quad 0x85ebca77c2b2ae63
xx_prime64_5:
    .quad 0x27d4eb2f165667c5
xx_prime32_1:
    .quad 0x9e3779b1
xx_prime_mx1:
    .quad 0x165667919e3779f9
xx_prime_mx2:
    .quad 0x9fb21c651e98df25
# what the eight accumulators start at
xx_init:
    .quad 0xc2b2ae3d                # PRIME32_3
    .quad 0x9e3779b185ebca87        # PRIME64_1
    .quad 0xc2b2ae3d27d4eb4f        # PRIME64_2
    .quad 0x165667b19e3779f9        # PRIME64_3
    .quad 0x85ebca77c2b2ae63        # PRIME64_4
    .quad 0x85ebca77                # PRIME32_2
    .quad 0x27d4eb2f165667c5        # PRIME64_5
    .quad 0x9e3779b1                # PRIME32_1
.balign 8
# the default secret, copied from the reference at its pinned tag
xx_secret:
    .byte 0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe
    .byte 0x7c, 0x01, 0x81, 0x2c, 0xf7, 0x21, 0xad, 0x1c
    .byte 0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb
    .byte 0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f
    .byte 0xcb, 0x79, 0xe6, 0x4e, 0xcc, 0xc0, 0xe5, 0x78
    .byte 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21
    .byte 0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e
    .byte 0xe0, 0x35, 0x90, 0xe6, 0x81, 0x3a, 0x26, 0x4c
    .byte 0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb
    .byte 0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3
    .byte 0x71, 0x64, 0x48, 0x97, 0xa2, 0x0d, 0xf9, 0x4e
    .byte 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8
    .byte 0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f
    .byte 0xf9, 0xdc, 0xbb, 0xc7, 0xc7, 0x0b, 0x4f, 0x1d
    .byte 0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31
    .byte 0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64
    .byte 0xea, 0xc5, 0xac, 0x83, 0x34, 0xd3, 0xeb, 0xc3
    .byte 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb
    .byte 0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49
    .byte 0xd3, 0x16, 0x55, 0x26, 0x29, 0xd4, 0x68, 0x9e
    .byte 0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc
    .byte 0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce
    .byte 0x45, 0xcb, 0x3a, 0x8f, 0x95, 0x16, 0x04, 0x28
    .byte 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e

.section .bss
.balign 8
xx_acc:
    .skip XX_ACCS * 8
xx_lo:
    .skip 8
xx_hi:
    .skip 8
xx_data:
    .skip 8
xx_stripe_n:
    .skip 8
