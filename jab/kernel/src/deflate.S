.include "riscv.inc"
.include "jab.inc"

# DEFLATE, the decompressor only: RFC 1951, the format inside every
# gzip file and inside every PNG. A stream is a run of blocks, each with
# a final bit and a type - stored, fixed Huffman, or dynamic Huffman.
# Literals and lengths share one alphabet where 256 ends the block and
# 257 upward are lengths with extra bits; distances have their own.
# Every Huffman code is canonical, so a table is nothing more than how
# many codes there are of each length and the symbols in order, which is
# what makes decoding a walk down the lengths rather than a lookup tree.
#
# The decoder writes straight into the program's own buffer, and a
# back-reference reads what it already wrote there, so the window is the
# output itself and no separate 32 KiB buffer exists. Everything it
# needs besides that lives in kernel bss, and every routine works in t
# registers over those globals rather than holding state in callee-saved
# ones, which keeps the whole file free of save-and-restore bookkeeping.
#
# The input is a segment of bytes, and a caller may give the decoder a
# way to ask for the next one: a PNG carries its stream cut into IDAT
# chunks, so png.S hands the decoder each chunk's data as the one before
# runs out, and the stream is never copied together. A gzip is one
# segment and gives no hook.

.set DF_MAX_BITS, 15
.set DF_LIT_SYMBOLS, 288
.set DF_DIST_SYMBOLS, 30
.set DF_CODE_SYMBOLS, 19
.set DF_LENGTHS, (DF_LIT_SYMBOLS + DF_DIST_SYMBOLS)

# what went wrong, as jab.gz.read reports it
.set DF_OK, 0
.set DF_ERR_INPUT, 1            # the stream ended in the middle of something
.set DF_ERR_OUTPUT, 2           # the buffer could not hold it
.set DF_ERR_BLOCK, 3            # a block type that does not exist
.set DF_ERR_STORED, 4           # a stored block's length disagrees with itself
.set DF_ERR_CODES, 5            # a code table that is not a Huffman code
.set DF_ERR_SYMBOL, 6           # a symbol no table can produce
.set DF_ERR_DISTANCE, 7         # a distance reaching before the output

.section .text

# deflate_inflate: a0 is the output buffer, a1 how much it holds, a2 the
# compressed bytes, a3 how many. a0 becomes the bytes written and a1 one
# of the codes above. The whole stream in one segment: deflate_begin
# with no hook, then deflate_run.
.global deflate_inflate
deflate_inflate:
    addi sp, sp, -16
    sd ra, 8(sp)
    li a4, 0
    call deflate_begin
    call deflate_run
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# deflate_begin: a0 is the output buffer, a1 how much it holds, a2 the
# first segment of compressed bytes, a3 how many, a4 a hook to call when
# a segment runs out, or 0 with none. A hook gives the decoder its next
# segment through deflate_segment and returns 1, or returns 0 when there
# is no more; it may use any register the decoder does not keep, which
# is all of them.
.global deflate_begin
deflate_begin:
    la t0, df_out
    sd a0, 0(t0)
    la t0, df_outcap
    sd a1, 0(t0)
    la t0, df_in
    sd a2, 0(t0)
    la t0, df_inlen
    sd a3, 0(t0)
    la t0, df_more
    sd a4, 0(t0)
    la t0, df_inpos
    sd zero, 0(t0)
    la t0, df_outpos
    sd zero, 0(t0)
    la t0, df_bitbuf
    sd zero, 0(t0)
    la t0, df_bitcnt
    sd zero, 0(t0)
    la t0, df_error
    sd zero, 0(t0)
    ret

# deflate_segment: a0 is the next segment of compressed bytes and a1 how
# many; what a hook calls before it returns 1.
.global deflate_segment
deflate_segment:
    la t0, df_in
    sd a0, 0(t0)
    la t0, df_inlen
    sd a1, 0(t0)
    la t0, df_inpos
    sd zero, 0(t0)
    ret

# deflate_byte: the next whole byte of the input, asking the hook for
# more when the segment has run out. a0 becomes the byte, or -1 when
# there is none. The bit buffer is left alone, so this reads what
# surrounds a stream - a zlib header before it, an Adler-32 after it -
# from the same cursor the blocks use.
.global deflate_byte
deflate_byte:
    addi sp, sp, -16
    sd ra, 8(sp)
1:
    la t0, df_inpos
    ld t1, 0(t0)
    la t2, df_inlen
    ld t2, 0(t2)
    bltu t1, t2, 2f
    call df_refill
    bnez a0, 1b
    li a0, -1
    j 3f
2:
    la t2, df_in
    ld t2, 0(t2)
    add t2, t2, t1
    lbu a0, 0(t2)
    addi t1, t1, 1
    sd t1, 0(t0)
3:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# deflate_run: the blocks, from where the input cursor stands to the one
# marked final. a0 becomes the bytes written and a1 one of the codes
# above. Fewer than eight bits are ever left in the bit buffer at the
# end, so the next whole byte is the first after the stream.
.global deflate_run
deflate_run:
    addi sp, sp, -16
    sd ra, 8(sp)
1:
    li a0, 1
    call df_bits
    mv t1, a0                   # the final bit
    la t0, df_last
    sd t1, 0(t0)
    li a0, 2
    call df_bits
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    beqz a0, 2f
    li t1, 1
    beq a0, t1, 3f
    li t1, 2
    beq a0, t1, 4f
    li t0, DF_ERR_BLOCK
    j 8f
2:
    call df_stored
    j 5f
3:
    call df_fixed
    j 5f
4:
    call df_dynamic
5:
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    la t0, df_last
    ld t0, 0(t0)
    beqz t0, 1b
9:
    la t0, df_error
    ld t0, 0(t0)
8:
    la t1, df_outpos
    ld a0, 0(t1)
    mv a1, t0
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# df_fail: t0 is a code; the first failure is the one kept.
df_fail:
    la t1, df_error
    ld t2, 0(t1)
    bnez t2, 1f
    sd t0, 0(t1)
1:
    ret

# df_refill: the segment has run out; ask the hook for another. a0
# becomes 1 with a new segment in place, 0 with none. Keeps nothing, so
# a caller saves what it holds in t registers first.
df_refill:
    la t0, df_more
    ld t0, 0(t0)
    beqz t0, 1f
    jr t0
1:
    li a0, 0
    ret

# df_bits: a0 is how many bits to take, at most 16, lowest first as
# DEFLATE writes them. a0 becomes their value, or 0 with the input
# error set once the stream has run out.
df_bits:
    mv t6, a0
    la t0, df_bitcnt
    ld t1, 0(t0)
    la t2, df_bitbuf
    ld t3, 0(t2)
1:
    bgeu t1, t6, 2f
    # another byte into the buffer
    la t4, df_inpos
    ld t5, 0(t4)
    la a0, df_inlen
    ld a0, 0(a0)
    bgeu t5, a0, 8f
    la a0, df_in
    ld a0, 0(a0)
    add a0, a0, t5
    lbu a0, 0(a0)
    sll a0, a0, t1
    or t3, t3, a0
    addi t5, t5, 1
    sd t5, 0(t4)
    addi t1, t1, 8
    j 1b
2:
    li t4, 1
    sll t4, t4, t6
    addi t4, t4, -1
    and a0, t3, t4
    srl t3, t3, t6
    sub t1, t1, t6
    la t4, df_bitcnt
    sd t1, 0(t4)
    la t4, df_bitbuf
    sd t3, 0(t4)
    ret
8:
    # the segment has run out: keep the buffer, ask for another, and go
    # on where it left off if one came
    la t4, df_bitcnt
    sd t1, 0(t4)
    la t4, df_bitbuf
    sd t3, 0(t4)
    la t4, df_want
    sd t6, 0(t4)
    addi sp, sp, -16
    sd ra, 8(sp)
    call df_refill
    ld ra, 8(sp)
    addi sp, sp, 16
    beqz a0, 9f
    la t4, df_want
    ld t6, 0(t4)
    la t0, df_bitcnt
    ld t1, 0(t0)
    la t2, df_bitbuf
    ld t3, 0(t2)
    j 1b
9:
    addi sp, sp, -16
    sd ra, 8(sp)
    li t0, DF_ERR_INPUT
    call df_fail
    ld ra, 8(sp)
    addi sp, sp, 16
    li a0, 0
    ret

# df_put: a0 is a byte for the output, which the program owns.
df_put:
    la t0, df_outpos
    ld t1, 0(t0)
    la t2, df_outcap
    ld t2, 0(t2)
    bgeu t1, t2, 8f
    la t3, df_out
    ld t3, 0(t3)
    add t3, t3, t1
    sb a0, 0(t3)
    addi t1, t1, 1
    sd t1, 0(t0)
    ret
8:
    addi sp, sp, -16
    sd ra, 8(sp)
    li t0, DF_ERR_OUTPUT
    call df_fail
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# df_stored: a block held as it is. The bits left in the buffer are
# dropped, then a length and its complement, then the bytes.
df_stored:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, df_bitcnt
    sd zero, 0(t0)
    la t0, df_bitbuf
    sd zero, 0(t0)
    li a0, 16
    call df_bits
    mv t3, a0
    la t0, df_scratch
    sd t3, 0(t0)
    li a0, 16
    call df_bits
    la t0, df_scratch
    ld t3, 0(t0)
    li t5, 0xffff               # too wide for an immediate
    xor t4, a0, t5
    and t4, t4, t5
    bne t3, t4, 8f
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
1:
    beqz t3, 9f
    la t0, df_scratch
    sd t3, 0(t0)
    call deflate_byte
    la t0, df_scratch
    ld t3, 0(t0)
    bltz a0, 7f
    call df_put
    la t0, df_scratch
    ld t3, 0(t0)
    addi t3, t3, -1
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    j 1b
7:
    li t0, DF_ERR_INPUT
    call df_fail
    j 9f
8:
    li t0, DF_ERR_STORED
    call df_fail
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# df_fixed: the tables every fixed block uses, built each time rather
# than kept, since building them is a few hundred stores.
df_fixed:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, df_lengths
    li t1, 0
1:
    li t2, 144
    bgeu t1, t2, 2f
    li t3, 8
    j 5f
2:
    li t2, 256
    bgeu t1, t2, 3f
    li t3, 9
    j 5f
3:
    li t2, 280
    bgeu t1, t2, 4f
    li t3, 7
    j 5f
4:
    li t3, 8
5:
    add t4, t0, t1
    sb t3, 0(t4)
    addi t1, t1, 1
    li t2, DF_LIT_SYMBOLS
    bltu t1, t2, 1b
    la a0, df_lencnt
    la a1, df_lensym
    la a2, df_lengths
    li a3, DF_LIT_SYMBOLS
    call df_construct
    la t0, df_lengths
    li t1, 0
6:
    add t2, t0, t1
    li t3, 5
    sb t3, 0(t2)
    addi t1, t1, 1
    li t2, DF_DIST_SYMBOLS
    bltu t1, t2, 6b
    la a0, df_distcnt
    la a1, df_distsym
    la a2, df_lengths
    li a3, DF_DIST_SYMBOLS
    call df_construct
    call df_codes
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# df_dynamic: the tables this block carries, themselves Huffman coded.
df_dynamic:
    addi sp, sp, -32
    sd ra, 24(sp)
    li a0, 5
    call df_bits
    addi t0, a0, 257
    sd t0, 0(sp)                # how many literal and length codes
    li a0, 5
    call df_bits
    addi t0, a0, 1
    sd t0, 8(sp)                # how many distance codes
    li a0, 4
    call df_bits
    addi t0, a0, 4
    sd t0, 16(sp)               # how many code-length codes
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    ld t0, 0(sp)
    li t1, DF_LIT_SYMBOLS
    bgtu t0, t1, 7f
    ld t0, 8(sp)
    li t1, DF_DIST_SYMBOLS
    bgtu t0, t1, 7f
    # the code-length code lengths, in the order the format names them
    la t0, df_lengths
    li t1, 0
    li t2, DF_CODE_SYMBOLS
1:
    bgeu t1, t2, 2f
    add t3, t0, t1
    sb zero, 0(t3)
    addi t1, t1, 1
    j 1b
2:
    li t1, 0
3:
    ld t2, 16(sp)
    bgeu t1, t2, 4f
    la t3, df_scratch
    sd t1, 0(t3)
    li a0, 3
    call df_bits
    la t3, df_scratch
    ld t1, 0(t3)
    la t3, df_clorder
    add t3, t3, t1
    lbu t3, 0(t3)
    la t4, df_lengths
    add t4, t4, t3
    sb a0, 0(t4)
    addi t1, t1, 1
    j 3b
4:
    la a0, df_codecnt
    la a1, df_codesym
    la a2, df_lengths
    li a3, DF_CODE_SYMBOLS
    call df_construct
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    # and with those, the lengths of the two real tables, run together
    li t1, 0
5:
    ld t2, 0(sp)
    ld t3, 8(sp)
    add t2, t2, t3
    bgeu t1, t2, 6f
    la t3, df_scratch
    sd t1, 0(t3)
    la a0, df_codecnt
    la a1, df_codesym
    call df_decode
    la t3, df_scratch
    ld t1, 0(t3)
    la t3, df_error
    ld t3, 0(t3)
    bnez t3, 9f
    li t2, 16
    bgeu a0, t2, 51f
    # a length of its own
    la t3, df_lengths
    add t3, t3, t1
    sb a0, 0(t3)
    addi t1, t1, 1
    j 5b
51:
    li t2, 16
    bne a0, t2, 52f
    # the one before it, three to six times
    beqz t1, 7f
    la t3, df_lengths
    add t3, t3, t1
    lbu t4, -1(t3)
    la t3, df_scratch2
    sd t4, 0(t3)
    li a0, 2
    call df_bits
    addi t5, a0, 3
    j 55f
52:
    li t2, 17
    bne a0, t2, 53f
    la t3, df_scratch2
    sd zero, 0(t3)
    li a0, 3
    call df_bits
    addi t5, a0, 3
    j 55f
53:
    li t2, 18
    bne a0, t2, 7f
    la t3, df_scratch2
    sd zero, 0(t3)
    li a0, 7
    call df_bits
    addi t5, a0, 11
55:
    la t3, df_scratch
    ld t1, 0(t3)
    la t3, df_scratch2
    ld t4, 0(t3)
    ld t2, 0(sp)
    ld t3, 8(sp)
    add t2, t2, t3
56:
    beqz t5, 5b
    bgeu t1, t2, 7f
    la t3, df_lengths
    add t3, t3, t1
    sb t4, 0(t3)
    addi t1, t1, 1
    addi t5, t5, -1
    j 56b
6:
    # the literal and length table, then the distance table after it
    la a0, df_lencnt
    la a1, df_lensym
    la a2, df_lengths
    ld a3, 0(sp)
    call df_construct
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    la a0, df_distcnt
    la a1, df_distsym
    la a2, df_lengths
    ld t0, 0(sp)
    add a2, a2, t0
    ld a3, 8(sp)
    call df_construct
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    call df_codes
    j 9f
7:
    li t0, DF_ERR_CODES
    call df_fail
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# df_construct: a0 is a count array of DF_MAX_BITS + 1 halfwords, a1 a
# symbol array of halfwords, a2 the lengths of a3 symbols. A canonical
# Huffman code is only its counts per length and its symbols in order,
# so that is all this builds. An incomplete code is refused, except the
# one distance code a block with no matches may carry.
df_construct:
    addi sp, sp, -16
    sd ra, 8(sp)
    # the counts
    li t0, 0
1:
    li t1, DF_MAX_BITS + 1
    bgeu t0, t1, 2f
    slli t1, t0, 1
    add t1, t1, a0
    sh zero, 0(t1)
    addi t0, t0, 1
    j 1b
2:
    li t0, 0
3:
    bgeu t0, a3, 4f
    add t1, a2, t0
    lbu t1, 0(t1)
    slli t2, t1, 1
    add t2, t2, a0
    lhu t3, 0(t2)
    addi t3, t3, 1
    sh t3, 0(t2)
    addi t0, t0, 1
    j 3b
4:
    # every symbol unused is no code at all, which a distance table is
    # allowed to be
    lhu t0, 0(a0)
    beq t0, a3, 9f
    # a code has to be complete: each length doubles what is left
    li t0, 1                    # codes left over
    li t1, 1                    # the length
5:
    li t2, DF_MAX_BITS + 1
    bgeu t1, t2, 6f
    slli t0, t0, 1
    slli t2, t1, 1
    add t2, t2, a0
    lhu t3, 0(t2)
    sub t0, t0, t3
    bltz t0, 8f
    addi t1, t1, 1
    j 5b
6:
    # where each length's symbols start
    la t4, df_offs
    sh zero, 0(t4)
    sh zero, 2(t4)
    li t1, 1
7:
    li t2, DF_MAX_BITS
    bgeu t1, t2, 71f
    slli t2, t1, 1
    add t2, t2, t4
    lhu t3, 0(t2)
    slli t5, t1, 1
    add t5, t5, a0
    lhu t5, 0(t5)
    add t3, t3, t5
    sh t3, 2(t2)
    addi t1, t1, 1
    j 7b
71:
    li t0, 0
72:
    bgeu t0, a3, 9f
    add t1, a2, t0
    lbu t1, 0(t1)
    beqz t1, 73f
    slli t2, t1, 1
    add t2, t2, t4
    lhu t3, 0(t2)
    slli t5, t3, 1
    add t5, t5, a1
    sh t0, 0(t5)
    addi t3, t3, 1
    sh t3, 0(t2)
73:
    addi t0, t0, 1
    j 72b
8:
    li t0, DF_ERR_CODES
    call df_fail
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# df_decode: a0 is a count array and a1 a symbol array. Walks the code
# lengths, taking one bit at a time, which is what a canonical code
# allows: at each length the codes of that length run consecutively, so
# a code within the count is the symbol at that offset.
# Every count here lives on the stack rather than in a t register,
# because df_bits is a call and a call keeps none of them.
df_decode:
    addi sp, sp, -64
    sd ra, 48(sp)
    sd a0, 0(sp)                # the counts
    sd a1, 8(sp)                # the symbols
    sd zero, 16(sp)             # the code so far
    sd zero, 24(sp)             # the first code of this length
    sd zero, 32(sp)             # where this length's symbols start
    li t0, 1
    sd t0, 40(sp)               # the length
1:
    ld t3, 40(sp)
    li t4, DF_MAX_BITS + 1
    bgeu t3, t4, 8f
    li a0, 1
    call df_bits
    la t4, df_error
    ld t4, 0(t4)
    bnez t4, 8f
    ld t0, 16(sp)
    or t0, t0, a0
    sd t0, 16(sp)
    ld t4, 0(sp)
    ld t3, 40(sp)
    slli t5, t3, 1
    add t5, t5, t4
    lhu t5, 0(t5)               # how many codes of this length
    ld t1, 24(sp)
    sub t6, t0, t1
    bgeu t6, t5, 2f
    ld t2, 32(sp)
    add t6, t6, t2
    slli t6, t6, 1
    ld t4, 8(sp)
    add t6, t6, t4
    lhu a0, 0(t6)
    j 9f
2:
    ld t2, 32(sp)
    add t2, t2, t5
    sd t2, 32(sp)
    add t1, t1, t5
    slli t1, t1, 1
    sd t1, 24(sp)
    ld t0, 16(sp)
    slli t0, t0, 1
    sd t0, 16(sp)
    ld t3, 40(sp)
    addi t3, t3, 1
    sd t3, 40(sp)
    j 1b
8:
    li t0, DF_ERR_SYMBOL
    call df_fail
    li a0, 0
9:
    ld ra, 48(sp)
    addi sp, sp, 64
    ret

# df_codes: the block's symbols, until the one that ends it. A literal
# is a byte; anything above 256 is a length with a distance after it,
# and the copy reads back what the output already holds.
df_codes:
    addi sp, sp, -32
    sd ra, 24(sp)
1:
    la a0, df_lencnt
    la a1, df_lensym
    call df_decode
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    li t0, 256
    beq a0, t0, 9f
    bgeu a0, t0, 2f
    call df_put
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    j 1b
2:
    addi t0, a0, -257
    li t1, 29
    bgeu t0, t1, 8f
    la t1, df_lenbase
    slli t2, t0, 1
    add t1, t1, t2
    lhu t1, 0(t1)
    sd t1, 0(sp)                # the length, before its extra bits
    la t1, df_lenextra
    add t1, t1, t0
    lbu a0, 0(t1)
    call df_bits
    ld t1, 0(sp)
    add t1, t1, a0
    sd t1, 0(sp)
    # the distance
    la a0, df_distcnt
    la a1, df_distsym
    call df_decode
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    li t1, DF_DIST_SYMBOLS
    bgeu a0, t1, 8f
    la t1, df_distbase
    slli t2, a0, 1
    add t1, t1, t2
    lhu t1, 0(t1)
    sd t1, 8(sp)
    la t1, df_distextra
    add t1, t1, a0
    lbu a0, 0(t1)
    call df_bits
    ld t1, 8(sp)
    add t1, t1, a0
    sd t1, 8(sp)
    la t0, df_error
    ld t0, 0(t0)
    bnez t0, 9f
    # the copy, from that far back in what is already written
    la t0, df_outpos
    ld t0, 0(t0)
    ld t1, 8(sp)
    bgtu t1, t0, 7f
    ld t2, 0(sp)                # how many bytes
3:
    beqz t2, 1b
    la t3, df_outpos
    ld t3, 0(t3)
    ld t1, 8(sp)
    sub t4, t3, t1
    la t5, df_out
    ld t5, 0(t5)
    add t4, t4, t5
    lbu a0, 0(t4)
    sd t2, 16(sp)
    call df_put
    ld t2, 16(sp)
    la t3, df_error
    ld t3, 0(t3)
    bnez t3, 9f
    addi t2, t2, -1
    j 3b
7:
    li t0, DF_ERR_DISTANCE
    call df_fail
    j 9f
8:
    li t0, DF_ERR_SYMBOL
    call df_fail
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

.section .rodata
.balign 2
# the order a dynamic block writes its code-length lengths in
df_clorder:
    .byte 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
.balign 2
df_lenbase:
    .2byte 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31
    .2byte 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
df_lenextra:
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2
    .byte 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
.balign 2
df_distbase:
    .2byte 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193
    .2byte 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145
    .2byte 8193, 12289, 16385, 24577
df_distextra:
    .byte 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6
    .byte 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13

.section .bss
.balign 8
df_in:
    .skip 8
df_inlen:
    .skip 8
df_inpos:
    .skip 8
df_out:
    .skip 8
df_outcap:
    .skip 8
df_outpos:
    .skip 8
df_bitbuf:
    .skip 8
df_bitcnt:
    .skip 8
df_error:
    .skip 8
df_last:
    .skip 8
df_scratch:
    .skip 8
df_scratch2:
    .skip 8
df_more:
    .skip 8
df_want:
    .skip 8
.balign 2
df_lencnt:
    .skip (DF_MAX_BITS + 1) * 2
df_distcnt:
    .skip (DF_MAX_BITS + 1) * 2
df_codecnt:
    .skip (DF_MAX_BITS + 1) * 2
df_offs:
    .skip (DF_MAX_BITS + 2) * 2
df_lensym:
    .skip DF_LIT_SYMBOLS * 2
df_distsym:
    .skip DF_DIST_SYMBOLS * 2
df_codesym:
    .skip DF_CODE_SYMBOLS * 2
df_lengths:
    .skip DF_LENGTHS
