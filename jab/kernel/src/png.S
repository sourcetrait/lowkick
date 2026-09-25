.include "riscv.inc"
.include "jab.inc"

# PNG, decoded in the kernel into a sprite the program owns (jab.inc):
# what GIMP 3 exports by default from any image mode, the five colour
# types at 8 bits a sample, grey and indexed at 1, 2, and 4 as well,
# never interlaced. A file is a signature and a run of chunks, each a
# length, a type, its data, and a CRC-32 over the type and the data; the
# IHDR says what the image is, PLTE and tRNS carry a palette and its
# transparency, the IDATs carry one zlib stream between them, and IEND
# closes the file. Everything else is skipped by rule.
#
# The stream is DEFLATE in a zlib jacket - two header bytes and an
# Adler-32 over what comes out - decoded by deflate.S, which asks
# png_more for each IDAT's data as the one before runs out, so the
# chunks are never copied together. The decode is in place: the stream
# inflates into the sprite's pixel area as filtered rows, each a filter
# byte and the row's samples; the filters are undone row by row against
# the row above; then the rows become native pixels, four bytes each,
# front to back where the source is wider (RGBA) and back to front where
# it is narrower, so nothing is read after it is overwritten. The buffer
# rule in jab.inc, four bytes a pixel and one a row, is what makes both
# passes fit.

# the signature and the chunk types as the big-endian words a read sees
.set PNG_SIG_LOW, 0x89504e47
.set PNG_SIG_HIGH, 0x0d0a1a0a
.set PNG_IHDR, 0x49484452
.set PNG_PLTE, 0x504c5445
.set PNG_TRNS, 0x74524e53
.set PNG_IDAT, 0x49444154
.set PNG_IEND, 0x49454e44
# the signature and the IHDR chunk, where the chunks after it begin
.set PNG_HEADER_END, 33
.set PNG_ADLER_MOD, 65521
# bytes between reductions of the Adler sums: both stay inside 64 bits
.set PNG_ADLER_RUN, 65536
# past this a width or height cannot fit any buffer a program has
.set PNG_SIDE_LIMIT, 65536
# a deflate code of 1 to 7 becomes JAB_PNG_INPUT to JAB_PNG_DISTANCE
.set PNG_DEFLATE_BASE, (JAB_PNG_INPUT - 1)

.section .text

# sys_png_size (jab.png.size): a0 is the PNG bytes and a1 how many. a0
# becomes the width and a1 the height, with a2 JAB_PNG_OK; or both 0
# with a2 the code.
.global sys_png_size
sys_png_size:
    ld a0, 80(sp)
    ld a1, 88(sp)
    call buffer_bounds
    ld a0, 80(sp)
    ld a1, 88(sp)
    call png_header
    bnez a0, 1f
    la t0, png_width
    ld t1, 0(t0)
    sd t1, 80(sp)
    la t0, png_height
    ld t1, 0(t0)
    sd t1, 88(sp)
    sd zero, 96(sp)
    j trap_return
1:
    sd zero, 80(sp)
    sd zero, 88(sp)
    sd a0, 96(sp)
    j trap_return

# sys_sprite_png (jab.sprite.png): a0 is the sprite record, a1 the PNG
# bytes, a2 how many, a3 how many bytes the record's buffer holds, a4
# the frames the sheet is cut into. a0 becomes a JAB_PNG_* code.
.global sys_sprite_png
sys_sprite_png:
    ld a0, 88(sp)
    ld a1, 96(sp)
    call buffer_bounds
    ld a0, 80(sp)
    ld a1, 104(sp)
    call buffer_bounds
    ld a0, 88(sp)
    ld a1, 96(sp)
    call png_header
    bnez a0, 9f
    # the frames divide the width
    ld s0, 112(sp)
    li a0, JAB_PNG_FRAMES
    beqz s0, 9f
    la t0, png_width
    ld t1, 0(t0)
    remu t2, t1, s0
    bnez t2, 9f
    # the buffer: four bytes a pixel and a byte a row, after the header
    li a0, JAB_PNG_SIZE
    li t2, PNG_SIDE_LIMIT
    bgeu t1, t2, 9f
    la t0, png_height
    ld t3, 0(t0)
    bgeu t3, t2, 9f
    mul t4, t1, t3
    slli t4, t4, 2
    add t4, t4, t3
    addi t4, t4, JAB_SPRITE_PIXELS
    ld t5, 104(sp)
    bltu t5, t4, 9f
    ld t0, 80(sp)
    addi t0, t0, JAB_SPRITE_PIXELS
    la t1, png_pixels
    sd t0, 0(t1)
    la t1, png_plte
    sd zero, 0(t1)
    la t1, png_plte_count
    sd zero, 0(t1)
    la t1, png_trns
    sd zero, 0(t1)
    la t1, png_trns_len
    sd zero, 0(t1)
    la t1, png_seen_idat
    sd zero, 0(t1)
    la t1, png_hook_code
    sd zero, 0(t1)
1:
    # the next chunk: its length and type, then its CRC
    la t0, png_pos
    ld s1, 0(t0)
    la t0, png_src
    ld s2, 0(t0)
    la t0, png_len
    ld s3, 0(t0)
    li a0, JAB_PNG_TRUNCATED
    addi t1, s1, 8
    bgtu t1, s3, 9f
    add a0, s2, s1
    call png_be32
    mv s4, a0
    add a0, s2, s1
    addi a0, a0, 4
    call png_be32
    mv s5, a0
    addi t1, s1, 12
    add t1, t1, s4
    li a0, JAB_PNG_TRUNCATED
    bgtu t1, s3, 9f
    add a0, s2, s1
    call png_crc_ok
    bnez a0, 2f
    li a0, JAB_PNG_CRC
    j 9f
2:
    li t0, PNG_PLTE
    bne s5, t0, 3f
    add t1, s2, s1
    addi t1, t1, 8
    la t0, png_plte
    sd t1, 0(t0)
    li t2, 3
    divu t3, s4, t2
    la t0, png_plte_count
    sd t3, 0(t0)
    j 7f
3:
    li t0, PNG_TRNS
    bne s5, t0, 4f
    add t1, s2, s1
    addi t1, t1, 8
    la t0, png_trns
    sd t1, 0(t0)
    la t0, png_trns_len
    sd s4, 0(t0)
    j 7f
4:
    li t0, PNG_IDAT
    bne s5, t0, 5f
    la t0, png_seen_idat
    ld t1, 0(t0)
    bnez t1, 7f                 # the stream has ended; the rest is ignored
    add a0, s2, s1
    addi a0, a0, 8
    mv a1, s4
    call png_stream
    bnez a0, 9f
    la t0, png_seen_idat
    li t1, 1
    sd t1, 0(t0)
    # the cursor moved with the stream: this is the chunk it stands on
    la t0, png_pos
    ld s1, 0(t0)
    add a0, s2, s1
    call png_be32
    mv s4, a0
    j 7f
5:
    li t0, PNG_IEND
    bne s5, t0, 7f
    la t0, png_seen_idat
    ld t1, 0(t0)
    li a0, JAB_PNG_TRUNCATED
    beqz t1, 9f
    j 8f
7:
    addi s1, s1, 12
    add s1, s1, s4
    la t0, png_pos
    sd s1, 0(t0)
    j 1b
8:
    # the rows, then the pixels, then the record
    call png_unfilter
    bnez a0, 9f
    call png_convert
    bnez a0, 9f
    ld t0, 80(sp)
    la t1, png_width
    ld t2, 0(t1)
    divu t2, t2, s0
    mv a0, t2
    addi a1, t0, JAB_SPRITE_WIDTH
    call png_le32_store
    la t1, png_height
    ld a0, 0(t1)
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_HEIGHT
    call png_le32_store
    mv a0, s0
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_FRAMES
    call png_le32_store
    li a0, JAB_PNG_OK
9:
    sd a0, 80(sp)
    j trap_return

# png_header: a0 is the PNG bytes and a1 how many. Reads the signature
# and the IHDR into the png_* state and stands the chunk cursor after
# them. a0 becomes JAB_PNG_OK, or NOT_PNG, TRUNCATED, CRC, UNSUPPORTED.
png_header:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, png_src
    sd a0, 0(t0)
    la t0, png_len
    sd a1, 0(t0)
    li t0, 8
    bltu a1, t0, 7f
    call png_be32
    li t0, PNG_SIG_LOW
    bne a0, t0, 7f
    la t0, png_src
    ld a0, 0(t0)
    addi a0, a0, 4
    call png_be32
    li t0, PNG_SIG_HIGH
    bne a0, t0, 7f
    la t0, png_len
    ld t1, 0(t0)
    li t0, PNG_HEADER_END
    bltu t1, t0, 8f
    # the first chunk is the IHDR, of thirteen bytes
    la t0, png_src
    ld a0, 0(t0)
    addi a0, a0, 8
    call png_be32
    li t0, 13
    bne a0, t0, 7f
    la t0, png_src
    ld a0, 0(t0)
    addi a0, a0, 12
    call png_be32
    li t0, PNG_IHDR
    bne a0, t0, 7f
    la t0, png_src
    ld a0, 0(t0)
    addi a0, a0, 8
    call png_crc_ok
    beqz a0, 6f
    la t0, png_src
    ld a0, 0(t0)
    addi a0, a0, 16
    call png_be32
    la t0, png_width
    sd a0, 0(t0)
    beqz a0, 7f
    la t0, png_src
    ld a0, 0(t0)
    addi a0, a0, 20
    call png_be32
    la t0, png_height
    sd a0, 0(t0)
    beqz a0, 7f
    la t0, png_src
    ld t1, 0(t0)
    lbu t2, 24(t1)              # bit depth
    lbu t3, 25(t1)              # colour type
    lbu t4, 26(t1)              # compression method, always 0
    lbu t5, 27(t1)              # filter method, always 0
    lbu t6, 28(t1)              # interlace method, 0 or Adam7
    bnez t4, 5f
    bnez t5, 5f
    bnez t6, 5f
    la t0, png_depth
    sd t2, 0(t0)
    la t0, png_type
    sd t3, 0(t0)
    # the channels each type carries, and the depths it may have
    li t4, 1
    beqz t3, 1f
    li t0, 3
    beq t3, t0, 1f
    li t0, 8
    bne t2, t0, 5f
    li t0, 2
    li t4, 3
    beq t3, t0, 2f
    li t0, 4
    li t4, 2
    beq t3, t0, 2f
    li t0, 6
    li t4, 4
    beq t3, t0, 2f
    j 5f
1:
    # grey and indexed: 1, 2, 4, or 8 bits
    li t0, 8
    beq t2, t0, 2f
    li t0, 4
    beq t2, t0, 2f
    li t0, 2
    beq t2, t0, 2f
    li t0, 1
    bne t2, t0, 5f
2:
    la t0, png_channels
    sd t4, 0(t0)
    # bytes a pixel for the filters, at least one; bytes a row; and the
    # filtered size of the whole image
    mul t5, t4, t2
    srli t6, t5, 3
    bnez t6, 3f
    li t6, 1
3:
    la t0, png_bpp
    sd t6, 0(t0)
    la t0, png_width
    ld t1, 0(t0)
    mul t5, t5, t1
    addi t5, t5, 7
    srli t5, t5, 3
    la t0, png_rowbytes
    sd t5, 0(t0)
    addi t5, t5, 1
    la t0, png_height
    ld t1, 0(t0)
    mul t5, t5, t1
    la t0, png_filtered
    sd t5, 0(t0)
    li t0, PNG_HEADER_END
    la t1, png_pos
    sd t0, 0(t1)
    li a0, JAB_PNG_OK
    j 9f
5:
    li a0, JAB_PNG_UNSUPPORTED
    j 9f
6:
    li a0, JAB_PNG_CRC
    j 9f
7:
    li a0, JAB_PNG_NOT_PNG
    j 9f
8:
    li a0, JAB_PNG_TRUNCATED
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# png_stream: a0 is the first IDAT's data and a1 how much. Inflates the
# zlib stream through every IDAT into the pixel area and checks its
# Adler-32. a0 becomes JAB_PNG_OK or the code.
png_stream:
    addi sp, sp, -32
    sd ra, 24(sp)
    mv a2, a0
    mv a3, a1
    la t0, png_pixels
    ld a0, 0(t0)
    la t0, png_filtered
    ld a1, 0(t0)
    la a4, png_more
    call deflate_begin
    # the zlib header: method 8 with a window, no preset dictionary, and
    # the two bytes together a multiple of 31
    call deflate_byte
    bltz a0, 7f
    sd a0, 0(sp)
    call deflate_byte
    bltz a0, 7f
    ld t0, 0(sp)
    andi t1, t0, 0x0f
    li t2, 8
    bne t1, t2, 6f
    andi t1, a0, 0x20
    bnez t1, 6f
    slli t0, t0, 8
    or t0, t0, a0
    li t1, 31
    remu t0, t0, t1
    bnez t0, 6f
    call deflate_run
    sd a0, 8(sp)                # the bytes written
    la t0, png_hook_code
    ld t0, 0(t0)
    bnez t0, 5f                 # a chunk the hook could not take
    beqz a1, 1f
    addi a0, a1, PNG_DEFLATE_BASE
    j 9f
1:
    la t0, png_filtered
    ld t0, 0(t0)
    ld t1, 8(sp)
    li a0, JAB_PNG_LENGTH
    bne t0, t1, 9f
    # the Adler-32 after the stream, big-endian, then over what came out
    sd zero, 16(sp)
    li t1, 4
    sd t1, 0(sp)
2:
    call deflate_byte
    bltz a0, 7f
    ld t0, 16(sp)
    slli t0, t0, 8
    or t0, t0, a0
    sd t0, 16(sp)
    ld t1, 0(sp)
    addi t1, t1, -1
    sd t1, 0(sp)
    bnez t1, 2b
    la t0, png_pixels
    ld a0, 0(t0)
    la t0, png_filtered
    ld a1, 0(t0)
    call png_adler
    ld t0, 16(sp)
    bne a0, t0, 6f
    li a0, JAB_PNG_OK
    j 9f
5:
    mv a0, t0
    j 9f
6:
    li a0, JAB_PNG_ZLIB
    j 9f
7:
    # the bytes ran out: the hook says why, or the file simply ended
    la t0, png_hook_code
    ld a0, 0(t0)
    bnez a0, 9f
    li a0, JAB_PNG_TRUNCATED
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# png_more: the decoder's hook. The IDAT the cursor stands on has run
# out; when the next chunk is an IDAT that checks, the cursor moves to
# it, its data becomes the decoder's segment, and a0 becomes 1. Else a0
# becomes 0 with the cursor where it was, and png_hook_code says why
# when a chunk was there but could not be taken.
png_more:
    addi sp, sp, -32
    sd ra, 24(sp)
    la t0, png_pos
    ld t1, 0(t0)
    la t0, png_src
    ld t2, 0(t0)
    add a0, t2, t1
    call png_be32               # this chunk's length
    la t0, png_pos
    ld t1, 0(t0)
    addi t1, t1, 12
    add t1, t1, a0              # the next chunk
    sd t1, 0(sp)
    la t0, png_len
    ld t3, 0(t0)
    addi t4, t1, 8
    bgtu t4, t3, 8f             # nothing after it
    la t0, png_src
    ld t2, 0(t0)
    add a0, t2, t1
    addi a0, a0, 4
    call png_be32
    li t0, PNG_IDAT
    bne a0, t0, 8f              # the stream's chunks are over
    ld t1, 0(sp)
    la t0, png_src
    ld t2, 0(t0)
    add a0, t2, t1
    call png_be32               # its length
    sd a0, 8(sp)
    ld t1, 0(sp)
    addi t4, t1, 12
    add t4, t4, a0
    la t0, png_len
    ld t3, 0(t0)
    li t5, JAB_PNG_TRUNCATED
    bgtu t4, t3, 7f
    la t0, png_src
    ld t2, 0(t0)
    add a0, t2, t1
    call png_crc_ok
    li t5, JAB_PNG_CRC
    beqz a0, 7f
    ld t1, 0(sp)
    la t0, png_pos
    sd t1, 0(t0)
    la t0, png_src
    ld t2, 0(t0)
    add a0, t2, t1
    addi a0, a0, 8
    ld a1, 8(sp)
    call deflate_segment
    li a0, 1
    j 9f
7:
    la t0, png_hook_code
    sd t5, 0(t0)
8:
    li a0, 0
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# png_crc_ok: a0 is a chunk, at its length field. a0 becomes 1 when the
# CRC-32 after its data answers for its type and data.
png_crc_ok:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    call png_be32
    sd a0, 8(sp)
    ld t0, 0(sp)
    addi a0, t0, 4
    ld a1, 8(sp)
    addi a1, a1, 4
    call gz_crc32
    sd a0, 16(sp)
    ld a0, 0(sp)
    ld t0, 8(sp)
    add a0, a0, t0
    addi a0, a0, 8
    call png_be32
    ld t0, 16(sp)
    xor a0, a0, t0
    seqz a0, a0
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# png_adler: a0 is a buffer and a1 how many bytes; a0 becomes their
# Adler-32. The two sums are reduced every PNG_ADLER_RUN bytes, which is
# as often as 64-bit registers need.
png_adler:
    li t0, 1
    li t1, 0
    li t5, PNG_ADLER_MOD
1:
    beqz a1, 3f
    li t2, PNG_ADLER_RUN
    bgeu a1, t2, 11f
    mv t2, a1
11:
    sub a1, a1, t2
2:
    lbu t3, 0(a0)
    add t0, t0, t3
    add t1, t1, t0
    addi a0, a0, 1
    addi t2, t2, -1
    bnez t2, 2b
    remu t0, t0, t5
    remu t1, t1, t5
    j 1b
3:
    slli a0, t1, 16
    or a0, a0, t0
    ret

# png_unfilter: undo each row's filter against the row above, in place.
# a0 becomes JAB_PNG_OK, or JAB_PNG_FILTER on a filter type that does
# not exist.
png_unfilter:
    la t0, png_pixels
    ld a0, 0(t0)                # the row's filter byte
    la t0, png_height
    ld a1, 0(t0)
    la t0, png_rowbytes
    ld a2, 0(t0)
    la t0, png_bpp
    ld a3, 0(t0)
    li a4, 0                    # the row above, none yet
1:
    beqz a1, 9f
    lbu t0, 0(a0)
    addi a5, a0, 1              # this row's bytes
    li t1, 4
    bgtu t0, t1, 8f
    beqz t0, 5f
    li t1, 1
    beq t0, t1, 2f
    li t1, 2
    beq t0, t1, 3f
    li t1, 3
    beq t0, t1, 4f
    # Paeth: the nearest of the byte to the left, above, and above left
    # to their sum less the corner, the left one winning a tie, then the
    # one above
    li t1, 0
41:
    bgeu t1, a2, 5f
    add t2, a5, t1
    lbu t3, 0(t2)
    li t4, 0
    bltu t1, a3, 42f
    sub t6, t2, a3
    lbu t4, 0(t6)
42:
    li t5, 0
    li t6, 0
    beqz a4, 43f
    add a6, a4, t1
    lbu t5, 0(a6)
    bltu t1, a3, 43f
    sub a6, a6, a3
    lbu t6, 0(a6)
43:
    sub a6, t5, t6              # how far the left one is from the sum
    bgez a6, 44f
    neg a6, a6
44:
    sub a7, t4, t6              # the one above
    bgez a7, 45f
    neg a7, a7
45:
    add t2, t4, t5
    sub t2, t2, t6
    sub t2, t2, t6              # the corner
    bgez t2, 46f
    neg t2, t2
46:
    bgtu a6, a7, 47f
    bgtu a6, t2, 47f
    mv t2, t4
    j 49f
47:
    bgtu a7, t2, 48f
    mv t2, t5
    j 49f
48:
    mv t2, t6
49:
    add t3, t3, t2
    add t2, a5, t1
    sb t3, 0(t2)
    addi t1, t1, 1
    j 41b
2:
    # Sub: the byte a pixel to the left; the first pixel has none
    mv t1, a3
21:
    bgeu t1, a2, 5f
    add t2, a5, t1
    lbu t3, 0(t2)
    sub t4, t2, a3
    lbu t4, 0(t4)
    add t3, t3, t4
    sb t3, 0(t2)
    addi t1, t1, 1
    j 21b
3:
    # Up: the byte above; the first row has none
    beqz a4, 5f
    li t1, 0
31:
    bgeu t1, a2, 5f
    add t2, a5, t1
    lbu t3, 0(t2)
    add t4, a4, t1
    lbu t4, 0(t4)
    add t3, t3, t4
    sb t3, 0(t2)
    addi t1, t1, 1
    j 31b
4:
    # Average: half the sum of the two, rounded down
    li t1, 0
32:
    bgeu t1, a2, 5f
    add t2, a5, t1
    lbu t3, 0(t2)
    li t4, 0
    bltu t1, a3, 33f
    sub t6, t2, a3
    lbu t4, 0(t6)
33:
    li t5, 0
    beqz a4, 34f
    add t6, a4, t1
    lbu t5, 0(t6)
34:
    add t4, t4, t5
    srli t4, t4, 1
    add t3, t3, t4
    sb t3, 0(t2)
    addi t1, t1, 1
    j 32b
5:
    mv a4, a5                   # this row is the next one's above
    add a0, a5, a2              # the next filter byte
    addi a1, a1, -1
    j 1b
8:
    li a0, JAB_PNG_FILTER
    ret
9:
    li a0, JAB_PNG_OK
    ret

# png_convert: the unfiltered rows become native pixels, in place, each
# stored as its four bytes so the record may sit anywhere. RGBA shrinks
# by the filter bytes and runs front to back; everything narrower grows
# and runs back to front. a0 becomes JAB_PNG_OK, or JAB_PNG_PALETTE for
# an indexed image with no palette or an index past it.
png_convert:
    addi sp, sp, -64
    sd ra, 56(sp)
    sd s1, 48(sp)
    sd s2, 40(sp)
    sd s3, 32(sp)
    sd s4, 24(sp)
    sd s5, 16(sp)
    sd s6, 8(sp)
    la t0, png_pixels
    ld a0, 0(t0)
    la t0, png_width
    ld a1, 0(t0)
    la t0, png_height
    ld a2, 0(t0)
    la t0, png_rowbytes
    ld a3, 0(t0)
    la t0, png_type
    ld a4, 0(t0)
    la t0, png_depth
    ld a5, 0(t0)
    la t0, png_plte
    ld s1, 0(t0)
    la t0, png_plte_count
    ld s2, 0(t0)
    la t0, png_trns
    ld s3, 0(t0)
    la t0, png_trns_len
    ld s4, 0(t0)
    li t0, 6
    beq a4, t0, 60f
    li t0, 2
    beq a4, t0, 20f
    li t0, 4
    beq a4, t0, 40f
    # grey and indexed: one sample a pixel, at depth bits, high bits
    # first; a grey sample scales to 255, an index reads the palette
    li s5, 1
    sll s5, s5, a5
    addi s5, s5, -1             # the sample mask
    li s6, 255
    divu s6, s6, s5             # what a grey sample scales by
    beqz a4, 1f
    beqz s1, 8f                 # indexed with no palette
    j 2f
1:
    # a grey key is two bytes; anything else is not one
    li t0, 2
    beq s4, t0, 2f
    li s3, 0
2:
    mv t2, a2                   # rows left
3:
    beqz t2, 9f
    addi t2, t2, -1
    addi t1, a3, 1
    mul t1, t1, t2
    add t1, t1, a0
    addi t1, t1, 1              # the row's samples
    mul t0, t2, a1
    add t0, t0, a1
    slli t0, t0, 2
    add t0, t0, a0              # a pixel past the row's last
    mv t3, a1                   # the pixel, from the last
4:
    beqz t3, 3b
    addi t3, t3, -1
    addi t0, t0, -4
    mul t4, t3, a5              # the sample's first bit
    srli t5, t4, 3
    add t5, t1, t5
    lbu t6, 0(t5)
    li t5, 8
    beq a5, t5, 5f
    andi t4, t4, 7
    sub t5, t5, a5
    sub t5, t5, t4
    srl t6, t6, t5
    and t6, t6, s5
5:
    bnez a4, 6f
    # grey
    mul t4, t6, s6
    li t5, 255
    beqz s3, 51f
    lbu a6, 1(s3)
    bne a6, t6, 51f
    lbu a6, 0(s3)
    bnez a6, 51f
    li t5, 0
51:
    sb t4, 0(t0)
    sb t4, 1(t0)
    sb t4, 2(t0)
    sb t5, 3(t0)
    j 4b
6:
    # indexed
    bgeu t6, s2, 8f
    li t4, 3
    mul t4, t4, t6
    add t4, t4, s1
    lbu a6, 0(t4)
    sb a6, 2(t0)
    lbu a6, 1(t4)
    sb a6, 1(t0)
    lbu a6, 2(t4)
    sb a6, 0(t0)
    li t5, 255
    bgeu t6, s4, 61f
    add t4, s3, t6
    lbu t5, 0(t4)
61:
    sb t5, 3(t0)
    j 4b
20:
    # RGB, three bytes a pixel, back to front; a key is six bytes
    li t0, 6
    beq s4, t0, 21f
    li s3, 0
21:
    mv t2, a2
22:
    beqz t2, 9f
    addi t2, t2, -1
    addi t1, a3, 1
    mul t1, t1, t2
    add t1, t1, a0
    add t1, t1, a3
    addi t1, t1, 1              # past the row's last sample
    mul t0, t2, a1
    add t0, t0, a1
    slli t0, t0, 2
    add t0, t0, a0
    mv t3, a1
23:
    beqz t3, 22b
    addi t3, t3, -1
    addi t0, t0, -4
    addi t1, t1, -3
    lbu t4, 0(t1)
    lbu t5, 1(t1)
    lbu t6, 2(t1)
    li a6, 255
    beqz s3, 24f
    lbu a7, 1(s3)
    bne a7, t4, 24f
    lbu a7, 3(s3)
    bne a7, t5, 24f
    lbu a7, 5(s3)
    bne a7, t6, 24f
    lbu a7, 0(s3)
    bnez a7, 24f
    lbu a7, 2(s3)
    bnez a7, 24f
    lbu a7, 4(s3)
    bnez a7, 24f
    li a6, 0
24:
    sb t6, 0(t0)
    sb t5, 1(t0)
    sb t4, 2(t0)
    sb a6, 3(t0)
    j 23b
40:
    # grey with alpha, two bytes a pixel, back to front
    mv t2, a2
41:
    beqz t2, 9f
    addi t2, t2, -1
    addi t1, a3, 1
    mul t1, t1, t2
    add t1, t1, a0
    add t1, t1, a3
    addi t1, t1, 1
    mul t0, t2, a1
    add t0, t0, a1
    slli t0, t0, 2
    add t0, t0, a0
    mv t3, a1
42:
    beqz t3, 41b
    addi t3, t3, -1
    addi t0, t0, -4
    addi t1, t1, -2
    lbu t4, 0(t1)
    lbu t5, 1(t1)
    sb t4, 0(t0)
    sb t4, 1(t0)
    sb t4, 2(t0)
    sb t5, 3(t0)
    j 42b
60:
    # RGBA, four bytes a pixel, front to back, each row's filter byte
    # stepped over
    mv t0, a0                   # the pixel
    addi t1, a0, 1              # the sample
    mv t2, a2
61:
    beqz t2, 9f
    addi t2, t2, -1
    mv t3, a1
62:
    beqz t3, 63f
    lbu t4, 0(t1)
    lbu t5, 1(t1)
    lbu t6, 2(t1)
    lbu a6, 3(t1)
    sb t6, 0(t0)
    sb t5, 1(t0)
    sb t4, 2(t0)
    sb a6, 3(t0)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t3, t3, -1
    j 62b
63:
    addi t1, t1, 1
    j 61b
8:
    li a0, JAB_PNG_PALETTE
    j 10f
9:
    li a0, JAB_PNG_OK
10:
    ld ra, 56(sp)
    ld s1, 48(sp)
    ld s2, 40(sp)
    ld s3, 32(sp)
    ld s4, 24(sp)
    ld s5, 16(sp)
    ld s6, 8(sp)
    addi sp, sp, 64
    ret

# png_be32: a0 is an address; a0 becomes the big-endian longword there,
# which is how PNG writes every number.
png_be32:
    lbu t0, 0(a0)
    lbu t1, 1(a0)
    lbu t2, 2(a0)
    lbu t3, 3(a0)
    slli t0, t0, 24
    slli t1, t1, 16
    slli t2, t2, 8
    or t0, t0, t1
    or t0, t0, t2
    or a0, t0, t3
    ret

# png_le32_store: a0 is a value and a1 an address; the low 32 bits are
# stored there little-endian, a byte at a time, as a record field.
png_le32_store:
    sb a0, 0(a1)
    srli t0, a0, 8
    sb t0, 1(a1)
    srli t0, a0, 16
    sb t0, 2(a1)
    srli t0, a0, 24
    sb t0, 3(a1)
    ret

.section .bss
.balign 8
png_src:
    .skip 8
png_len:
    .skip 8
png_pos:
    .skip 8
png_width:
    .skip 8
png_height:
    .skip 8
png_depth:
    .skip 8
png_type:
    .skip 8
png_channels:
    .skip 8
png_bpp:
    .skip 8
png_rowbytes:
    .skip 8
png_filtered:
    .skip 8
png_pixels:
    .skip 8
png_plte:
    .skip 8
png_plte_count:
    .skip 8
png_trns:
    .skip 8
png_trns_len:
    .skip 8
png_seen_idat:
    .skip 8
png_hook_code:
    .skip 8
