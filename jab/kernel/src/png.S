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
# The file comes from one of two sources through png_fetch: bytes the
# program holds (jab.sprite.png) or a file on a romfs disk, read through
# the kernel's own bounce (jab.sprite.load), so a program need hold no
# buffer for a file at all. Either way the bytes arrive in pieces: the
# chunk headers and the small chunks into kernel buffers, each IDAT's
# data as segments of PNG_SEGMENT bytes handed to deflate.S as the one
# before runs out, with a CRC running over each chunk as it passes and
# compared at its end. The stream is DEFLATE in a zlib jacket - two
# header bytes and an Adler-32 over what comes out. The decode is in
# place: the stream inflates into the destination as filtered rows, each
# a filter byte and the row's samples; the filters are undone row by row
# against the row above; then the rows become native pixels, four bytes
# each, front to back where the source is wider (RGBA) and back to front
# where it is narrower, so nothing is read after it is overwritten. The
# buffer rule in jab.inc, four bytes a pixel and one a row, is what
# makes both passes fit.

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
# a piece of a chunk, as it is read and handed to the decoder
.set PNG_SEGMENT, 2048
.set PNG_PLTE_MAX, 768
.set PNG_TRNS_MAX, 256
# the sources
.set PNG_FROM_MEMORY, 0
.set PNG_FROM_DISK, 1
# a frame's name, digits and .png
.set PNG_NAME_BYTES, 32

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
    call png_from_memory
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
# the frames the sheet is cut into, top to bottom. a0 becomes a
# JAB_PNG_* code.
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
    call png_from_memory
    call png_header
    bnez a0, 9f
    # the frames divide the height
    ld s0, 112(sp)
    li a0, JAB_PNG_FRAMES
    beqz s0, 9f
    la t0, png_height
    ld t1, 0(t0)
    remu t2, t1, s0
    bnez t2, 9f
    # the buffer: four bytes a pixel and a byte a row, after the header
    la t0, png_width
    ld a0, 0(t0)
    mv a1, t1
    ld a2, 104(sp)
    call png_room
    bnez a0, 9f
    ld a0, 80(sp)
    addi a0, a0, JAB_SPRITE_PIXELS
    call png_decode
    bnez a0, 9f
    la t1, png_width
    ld a0, 0(t1)
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_WIDTH
    call png_le32_store
    la t1, png_height
    ld a0, 0(t1)
    divu a0, a0, s0
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_HEIGHT
    call png_le32_store
    mv a0, s0
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_FRAMES
    call png_le32_store
    ld a0, 80(sp)
    call sprite_spans
    li a0, JAB_PNG_OK
9:
    sd a0, 80(sp)
    j trap_return

# sys_sprite_load (jab.sprite.load): a0 is the sprite record, a1 the
# disk, a2 a path to a directory on it, a3 how many bytes the record's
# buffer holds. The frames are the files 0.png, 1.png, and on in that
# directory, in order until one is missing, each decoded straight off
# the disk into its own block of the record; all must be one size. a0
# becomes a JAB_PNG_* code: NOT_FOUND when the directory or 0.png is
# not there, FRAMES when a frame's size differs from the first's, SIZE
# when the buffer is short, else a frame's own code.
.global sys_sprite_load
sys_sprite_load:
    ld a0, 80(sp)
    ld a1, 104(sp)
    call buffer_bounds
    ld a0, 96(sp)
    call message_bounds
    mv s1, a0                   # the path
    mv s2, a1                   # where it ends
    call block_probe
    ld a0, 88(sp)
    call romfs_disk
    mv s0, a0                   # the disk's index
    # the directory
    mv a0, s0
    li a1, JAB_ROMFS_ROOT
    mv a2, s1
    mv a3, s2
    call romfs_lookup
    bnez a0, 7f
    mv s3, a1                   # the directory's header
    la t0, romfs_scratch
    lwu t1, JAB_ROMFS_NEXT(t0)
    andi t1, t1, JAB_ROMFS_TYPE
    li t2, JAB_ROMFS_DIRECTORY
    bne t1, t2, 7f
    # the first frame says what size every frame is; then count them
    li a0, 0
    call png_frame_source
    bnez a0, 9f
    call png_header
    bnez a0, 9f
    la t0, png_width
    ld s4, 0(t0)                # the frames' width
    la t0, png_height
    ld s5, 0(t0)                # and height
    li s6, 1                    # how many
1:
    mv a0, s6
    call png_frame_source
    bnez a0, 2f
    addi s6, s6, 1
    j 1b
2:
    li t0, JAB_PNG_NOT_FOUND
    bne a0, t0, 9f              # a frame that is there but unreadable
    # the room: every frame's block, and a row on the end
    mv a0, s4
    mul a1, s5, s6
    ld a2, 104(sp)
    call png_room
    bnez a0, 9f
    # each frame into its own block
    mul s7, s4, s5
    slli s7, s7, 2              # a frame's bytes
    li s8, 0
3:
    bgeu s8, s6, 4f
    mv a0, s8
    call png_frame_source
    bnez a0, 9f
    call png_header
    bnez a0, 9f
    li a0, JAB_PNG_FRAMES
    la t0, png_width
    ld t1, 0(t0)
    bne t1, s4, 9f
    la t0, png_height
    ld t1, 0(t0)
    bne t1, s5, 9f
    mul t0, s8, s7
    ld a0, 80(sp)
    addi a0, a0, JAB_SPRITE_PIXELS
    add a0, a0, t0
    call png_decode
    bnez a0, 9f
    addi s8, s8, 1
    j 3b
4:
    mv a0, s4
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_WIDTH
    call png_le32_store
    mv a0, s5
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_HEIGHT
    call png_le32_store
    mv a0, s6
    ld t0, 80(sp)
    addi a1, t0, JAB_SPRITE_FRAMES
    call png_le32_store
    ld a0, 80(sp)
    call sprite_spans
    li a0, JAB_PNG_OK
    j 9f
7:
    li a0, JAB_PNG_NOT_FOUND
9:
    sd a0, 80(sp)
    j trap_return

# png_frame_source: a0 is a frame's number; s0 the disk's index and s3
# the directory, as sys_sprite_load holds them. Looks up <number>.png
# there and, when it is a regular file, makes it the source. a0
# becomes JAB_PNG_OK, or JAB_PNG_NOT_FOUND.
png_frame_source:
    addi sp, sp, -16
    sd ra, 8(sp)
    # the name: the digits, then .png
    la t1, png_name
    addi t1, t1, PNG_NAME_BYTES - 1
    sb zero, 0(t1)
    addi t1, t1, -1
    li t2, 'g'
    sb t2, 0(t1)
    addi t1, t1, -1
    li t2, 'n'
    sb t2, 0(t1)
    addi t1, t1, -1
    li t2, 'p'
    sb t2, 0(t1)
    addi t1, t1, -1
    li t2, '.'
    sb t2, 0(t1)
    li t3, 10
1:
    remu t4, a0, t3
    divu a0, a0, t3
    addi t4, t4, '0'
    addi t1, t1, -1
    sb t4, 0(t1)
    bnez a0, 1b
    mv a2, t1
    la a3, png_name
    addi a3, a3, PNG_NAME_BYTES - 1
    mv a0, s0
    mv a1, s3
    call romfs_lookup
    bnez a0, 8f
    la t0, romfs_scratch
    lwu t1, JAB_ROMFS_NEXT(t0)
    andi t1, t1, JAB_ROMFS_TYPE
    li t2, JAB_ROMFS_REGULAR
    bne t1, t2, 8f
    lwu t1, JAB_ROMFS_SIZE(t0)
    la t0, png_len
    sd t1, 0(t0)
    # where the file's bytes begin: after the header and its name
    mv a0, s0
    la a2, romfs_scratch
    lwu a1, JAB_ROMFS_OFFSET(a2)
    sd a1, 0(sp)
    call romfs_entry
    ld t0, 0(sp)
    add t0, t0, a0
    la t1, png_data
    sd t0, 0(t1)
    la t1, png_disk
    sd s0, 0(t1)
    la t1, png_kind
    li t0, PNG_FROM_DISK
    sd t0, 0(t1)
    li a0, JAB_PNG_OK
    j 9f
8:
    li a0, JAB_PNG_NOT_FOUND
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# png_from_memory: a0 is the bytes the program holds and a1 how many;
# they become the source.
png_from_memory:
    la t0, png_src
    sd a0, 0(t0)
    la t0, png_len
    sd a1, 0(t0)
    la t0, png_kind
    sd zero, 0(t0)
    ret

# png_fetch: a0 is an offset into the file, a1 how many bytes, a2 where
# they go; the caller has kept the range inside the file. From memory
# a copy; from a disk, through the romfs bounce, as many sectors as it
# holds at a time.
png_fetch:
    addi sp, sp, -48
    sd ra, 40(sp)
    la t0, png_kind
    ld t0, 0(t0)
    bnez t0, 1f
    la t0, png_src
    ld t0, 0(t0)
    add t1, t0, a0              # the bytes, where the program holds them
    mv a0, a2
    mv a2, a1
    mv a1, t1
    call copy_bytes
    j 9f
1:
    sd a0, 0(sp)                # the offset
    sd a1, 8(sp)                # bytes to go
    sd a2, 16(sp)               # the destination
2:
    ld t0, 8(sp)
    beqz t0, 9f
    la t0, png_disk
    ld a0, 0(t0)
    la t0, png_data
    ld a1, 0(t0)
    ld t0, 0(sp)
    add a1, a1, t0
    call romfs_window
    ld t0, 8(sp)
    bgeu t0, a1, 21f
    mv a1, t0
21:
    sd a1, 24(sp)
    mv a2, a1
    mv a1, a0
    ld a0, 16(sp)
    call copy_bytes
    ld t0, 24(sp)
    ld t1, 0(sp)
    add t1, t1, t0
    sd t1, 0(sp)
    ld t1, 8(sp)
    sub t1, t1, t0
    sd t1, 8(sp)
    ld t1, 16(sp)
    add t1, t1, t0
    sd t1, 16(sp)
    j 2b
9:
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# png_be32_at: a0 is an address of four bytes in a kernel buffer; a0
# becomes the big-endian longword there, which is how PNG writes every
# number.
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

# png_room: a0 is a width, a1 a height (of the whole sheet), a2 how
# many bytes the record's buffer holds. a0 becomes JAB_PNG_OK when the
# buffer reaches the rule, four bytes a pixel and four bytes a row
# after the header - the row's filter byte on the way in, its span on
# the way out - or JAB_PNG_SIZE.
png_room:
    li t2, PNG_SIDE_LIMIT
    bgeu a0, t2, 8f
    bgeu a1, t2, 8f
    addi t4, a0, 1
    mul t4, t4, a1
    slli t4, t4, 2
    addi t4, t4, JAB_SPRITE_PIXELS
    bltu a2, t4, 8f
    li a0, JAB_PNG_OK
    ret
8:
    li a0, JAB_PNG_SIZE
    ret

# png_header: reads the source's signature and IHDR into the png_*
# state and stands the chunk cursor after them. a0 becomes JAB_PNG_OK,
# or NOT_PNG, TRUNCATED, CRC, UNSUPPORTED.
png_header:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, png_len
    ld t1, 0(t0)
    li t0, 8
    bltu t1, t0, 7f
    li a0, 0
    li a1, 8
    la a2, png_head
    call png_fetch
    la a0, png_head
    call png_be32
    li t0, PNG_SIG_LOW
    bne a0, t0, 7f
    la a0, png_head
    addi a0, a0, 4
    call png_be32
    li t0, PNG_SIG_HIGH
    bne a0, t0, 7f
    la t0, png_len
    ld t1, 0(t0)
    li t0, PNG_HEADER_END
    bltu t1, t0, 8f
    li a0, 8
    li a1, PNG_HEADER_END - 8
    la a2, png_head
    addi a2, a2, 8
    call png_fetch
    # the first chunk is the IHDR, of thirteen bytes, and it checks
    la a0, png_head
    addi a0, a0, 8
    call png_be32
    li t0, 13
    bne a0, t0, 7f
    la a0, png_head
    addi a0, a0, 12
    call png_be32
    li t0, PNG_IHDR
    bne a0, t0, 7f
    la a0, png_head
    addi a0, a0, 12
    li a1, 17
    call gz_crc32
    la t0, png_crc_word
    sd a0, 0(t0)
    la a0, png_head
    addi a0, a0, 29
    call png_be32
    la t0, png_crc_word
    ld t0, 0(t0)
    bne a0, t0, 6f
    la a0, png_head
    addi a0, a0, 16
    call png_be32
    la t0, png_width
    sd a0, 0(t0)
    beqz a0, 7f
    la a0, png_head
    addi a0, a0, 20
    call png_be32
    la t0, png_height
    sd a0, 0(t0)
    beqz a0, 7f
    la t1, png_head
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

# png_decode: a0 is where the pixels go, after png_header has read the
# source. The chunk walk, the stream, the filters, the conversion. a0
# becomes JAB_PNG_OK or the code.
png_decode:
    addi sp, sp, -48
    sd ra, 40(sp)
    la t0, png_pixels
    sd a0, 0(t0)
    la t0, png_plte
    sd zero, 0(t0)
    la t0, png_plte_count
    sd zero, 0(t0)
    la t0, png_trns
    sd zero, 0(t0)
    la t0, png_trns_len
    sd zero, 0(t0)
    la t0, png_seen_idat
    sd zero, 0(t0)
    la t0, png_hook_code
    sd zero, 0(t0)
1:
    # the next chunk: its length and type
    la t0, png_pos
    ld t1, 0(t0)
    sd t1, 0(sp)                # the chunk
    la t0, png_len
    ld t2, 0(t0)
    li a0, JAB_PNG_TRUNCATED
    addi t3, t1, 8
    bgtu t3, t2, 9f
    mv a0, t1
    li a1, 8
    la a2, png_chunkhead
    call png_fetch
    la a0, png_chunkhead
    call png_be32
    sd a0, 8(sp)                # its length
    la a0, png_chunkhead
    addi a0, a0, 4
    call png_be32
    sd a0, 16(sp)               # its type
    ld t1, 0(sp)
    ld t2, 8(sp)
    addi t3, t1, 12
    add t3, t3, t2
    la t0, png_len
    ld t0, 0(t0)
    li a0, JAB_PNG_TRUNCATED
    bgtu t3, t0, 9f
    ld t0, 16(sp)
    li t1, PNG_PLTE
    bne t0, t1, 2f
    # the palette, into its buffer, and checked
    ld a1, 8(sp)
    li a0, JAB_PNG_UNSUPPORTED
    li t0, PNG_PLTE_MAX
    bgtu a1, t0, 9f
    ld a0, 0(sp)
    addi a0, a0, 8
    la a2, png_plte_buf
    call png_fetch
    la t0, png_plte
    la t1, png_plte_buf
    sd t1, 0(t0)
    ld t1, 8(sp)
    li t2, 3
    divu t1, t1, t2
    la t0, png_plte_count
    sd t1, 0(t0)
    j 6f
2:
    li t1, PNG_TRNS
    bne t0, t1, 3f
    ld a1, 8(sp)
    li a0, JAB_PNG_UNSUPPORTED
    li t0, PNG_TRNS_MAX
    bgtu a1, t0, 9f
    ld a0, 0(sp)
    addi a0, a0, 8
    la a2, png_trns_buf
    call png_fetch
    la t0, png_trns
    la t1, png_trns_buf
    sd t1, 0(t0)
    ld t1, 8(sp)
    la t0, png_trns_len
    sd t1, 0(t0)
    j 6f
3:
    li t1, PNG_IDAT
    bne t0, t1, 4f
    la t0, png_seen_idat
    ld t1, 0(t0)
    bnez t1, 6f                 # the stream has ended; the rest is checked and ignored
    ld a0, 0(sp)
    ld a1, 8(sp)
    call png_stream
    bnez a0, 9f
    la t0, png_seen_idat
    li t1, 1
    sd t1, 0(t0)
    # the cursor moved with the stream: the chunk it stands on is
    # checked whole, since the stream may have ended inside it
    la t0, png_pos
    ld t1, 0(t0)
    sd t1, 0(sp)
    la t0, png_chunk_len
    ld t1, 0(t0)
    sd t1, 8(sp)
    j 6f
4:
    li t1, PNG_IEND
    bne t0, t1, 6f
    la t0, png_seen_idat
    ld t1, 0(t0)
    li a0, JAB_PNG_TRUNCATED
    beqz t1, 9f
    ld a0, 0(sp)
    ld a1, 8(sp)
    call png_chunk_ok
    beqz a0, 8f
    j 7f
6:
    # every chunk answers for itself
    ld a0, 0(sp)
    ld a1, 8(sp)
    call png_chunk_ok
    beqz a0, 8f
    ld t1, 0(sp)
    ld t2, 8(sp)
    addi t1, t1, 12
    add t1, t1, t2
    la t0, png_pos
    sd t1, 0(t0)
    j 1b
7:
    # the rows, then the pixels
    call png_unfilter
    bnez a0, 9f
    call png_convert
    j 9f
8:
    li a0, JAB_PNG_CRC
9:
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# png_chunk_ok: a0 is a chunk's offset and a1 its length. Runs the
# CRC-32 over its type and data in pieces and compares it with the one
# after the data. a0 becomes 1 when they agree.
png_chunk_ok:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    call gz_crc_begin
    sd a0, 16(sp)               # the running state
    ld a0, 0(sp)
    addi a0, a0, 4
    li a1, 4
    la a2, png_seg
    call png_fetch
    ld a0, 16(sp)
    la a1, png_seg
    li a2, 4
    call gz_crc_update
    sd a0, 16(sp)
    sd zero, 24(sp)             # of the data, done so far
1:
    ld t0, 24(sp)
    ld t1, 8(sp)
    bgeu t0, t1, 2f
    sub t2, t1, t0
    li t3, PNG_SEGMENT
    bgeu t2, t3, 11f
    mv t3, t2
11:
    sd t3, 32(sp)
    ld a0, 0(sp)
    addi a0, a0, 8
    add a0, a0, t0
    mv a1, t3
    la a2, png_seg
    call png_fetch
    ld a0, 16(sp)
    la a1, png_seg
    ld a2, 32(sp)
    call gz_crc_update
    sd a0, 16(sp)
    ld t0, 24(sp)
    ld t1, 32(sp)
    add t0, t0, t1
    sd t0, 24(sp)
    j 1b
2:
    ld a0, 16(sp)
    call gz_crc_end
    sd a0, 16(sp)
    ld a0, 0(sp)
    ld t0, 8(sp)
    add a0, a0, t0
    addi a0, a0, 8
    li a1, 4
    la a2, png_seg
    call png_fetch
    la a0, png_seg
    call png_be32
    ld t0, 16(sp)
    xor a0, a0, t0
    seqz a0, a0
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# png_stream: a0 is the first IDAT's offset and a1 its length. Inflates
# the zlib stream through every IDAT into the pixel area and checks its
# Adler-32; the hook checks each chunk's CRC as it is left behind. a0
# becomes JAB_PNG_OK or the code.
png_stream:
    addi sp, sp, -32
    sd ra, 24(sp)
    la t0, png_pos
    sd a0, 0(t0)
    la t0, png_chunk_len
    sd a1, 0(t0)
    la t0, png_chunk_done
    sd zero, 0(t0)
    call png_chunk_begin
    la t0, png_pixels
    ld a0, 0(t0)
    la t0, png_filtered
    ld a1, 0(t0)
    la a2, png_seg
    li a3, 0                    # no segment yet: the hook gives the first
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

# png_chunk_begin: start the running CRC of the chunk the cursor stands
# on, over its type.
png_chunk_begin:
    addi sp, sp, -16
    sd ra, 8(sp)
    call gz_crc_begin
    la t0, png_crc_state
    sd a0, 0(t0)
    la t0, png_pos
    ld a0, 0(t0)
    addi a0, a0, 4
    li a1, 4
    la a2, png_seg
    call png_fetch
    la t0, png_crc_state
    ld a0, 0(t0)
    la a1, png_seg
    li a2, 4
    call gz_crc_update
    la t0, png_crc_state
    sd a0, 0(t0)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# png_more: the decoder's hook. The next piece of the IDAT the cursor
# stands on becomes the decoder's segment, through png_seg with the
# CRC running; when that chunk is spent its CRC is compared, and when
# the next chunk is an IDAT the cursor moves to it and its first piece
# follows. a0 becomes 1 with a segment in place, else 0 with the cursor
# where it was, and png_hook_code says why when a chunk was there but
# could not be taken.
png_more:
    addi sp, sp, -32
    sd ra, 24(sp)
1:
    la t0, png_chunk_done
    ld t1, 0(t0)
    la t0, png_chunk_len
    ld t2, 0(t0)
    bgeu t1, t2, 3f
    # a piece of this chunk
    sub t3, t2, t1
    li t4, PNG_SEGMENT
    bgeu t3, t4, 2f
    mv t4, t3
2:
    sd t4, 0(sp)
    la t0, png_pos
    ld a0, 0(t0)
    addi a0, a0, 8
    add a0, a0, t1
    mv a1, t4
    la a2, png_seg
    call png_fetch
    la t0, png_crc_state
    ld a0, 0(t0)
    la a1, png_seg
    ld a2, 0(sp)
    call gz_crc_update
    la t0, png_crc_state
    sd a0, 0(t0)
    la t0, png_chunk_done
    ld t1, 0(t0)
    ld t2, 0(sp)
    add t1, t1, t2
    sd t1, 0(t0)
    la a0, png_seg
    ld a1, 0(sp)
    call deflate_segment
    li a0, 1
    j 9f
3:
    # this chunk is spent: its CRC must answer
    la t0, png_crc_state
    ld a0, 0(t0)
    call gz_crc_end
    sd a0, 8(sp)
    la t0, png_pos
    ld a0, 0(t0)
    la t0, png_chunk_len
    ld t1, 0(t0)
    add a0, a0, t1
    addi a0, a0, 8
    li a1, 4
    la a2, png_chunkhead
    call png_fetch
    la a0, png_chunkhead
    call png_be32
    ld t0, 8(sp)
    li t5, JAB_PNG_CRC
    bne a0, t0, 7f
    # the next chunk
    la t0, png_pos
    ld t1, 0(t0)
    la t0, png_chunk_len
    ld t2, 0(t0)
    addi t1, t1, 12
    add t1, t1, t2
    sd t1, 16(sp)
    la t0, png_len
    ld t3, 0(t0)
    addi t4, t1, 8
    bgtu t4, t3, 8f             # nothing after it
    mv a0, t1
    li a1, 8
    la a2, png_chunkhead
    call png_fetch
    la a0, png_chunkhead
    addi a0, a0, 4
    call png_be32
    li t0, PNG_IDAT
    bne a0, t0, 8f              # the stream's chunks are over
    la a0, png_chunkhead
    call png_be32
    ld t1, 16(sp)
    addi t4, t1, 12
    add t4, t4, a0
    la t0, png_len
    ld t3, 0(t0)
    li t5, JAB_PNG_TRUNCATED
    bgtu t4, t3, 7f
    la t0, png_pos
    sd t1, 0(t0)
    la t0, png_chunk_len
    sd a0, 0(t0)
    la t0, png_chunk_done
    sd zero, 0(t0)
    call png_chunk_begin
    j 1b
7:
    la t0, png_hook_code
    sd t5, 0(t0)
8:
    li a0, 0
9:
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

.section .bss
.balign 8
png_kind:
    .skip 8
png_src:
    .skip 8
png_len:
    .skip 8
png_disk:
    .skip 8
png_data:
    .skip 8
png_pos:
    .skip 8
png_chunk_len:
    .skip 8
png_chunk_done:
    .skip 8
png_crc_state:
    .skip 8
png_crc_word:
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
png_head:
    .skip 40
png_chunkhead:
    .skip 8
png_name:
    .skip PNG_NAME_BYTES
png_plte_buf:
    .skip PNG_PLTE_MAX
png_trns_buf:
    .skip PNG_TRNS_MAX
png_seg:
    .skip PNG_SEGMENT
