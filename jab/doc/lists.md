# Lists

Some Jab calls hand back more than a register holds. A list of the
disks on the machine, or of the entries in a directory, is a set of
records rather than a number. Every call that does this works the same
way, so learning one teaches all of them.

## The program owns the memory

The kernel never allocates. Your program declares a buffer, tells the
call how many records that buffer holds, and the kernel fills it. The
kernel writes nothing outside your program's window, and it writes no
more records than you said would fit.

```
        .lcomm  disks, JAB_BLOCK_LIST_SIZE

        jab.block.list disks
```

## What comes back

Two registers come back from every list call.

`a0` is how many records the kernel wrote. Walk exactly that many.

`a1` is where the next page starts, and 0 when there is no next page.
Pass it straight back in as the cursor to get the page after this one.

```
        la      t0, disks
        jab.block.list t0
        beqz    a0, none
        mv      t1, a0
1:      lbu     t2, JAB_BLOCK_ID(t0)
        ld      t3, JAB_BLOCK_SECTORS(t0)
        ...
        addi    t0, t0, JAB_BLOCK_ENTRY
        addi    t1, t1, -1
        bnez    t1, 1b
```

## Paging

A directory can hold more entries than your buffer does. The cursor is
what makes that work. Start at zero, and keep going while `a1` is not
zero.

```
        mv      t3, zero                  # start at the first entry
1:      jab.romfs.list page, t0, t1, t3, 16
        ...                               # a0 records are in the page
        mv      t3, a1
        bnez    a1, 1b
```

The kernel remembers nothing between the calls. The cursor is yours to
hold, so two parts of your program can walk two different directories
at once without disturbing each other, and a page you ask for twice
comes back the same both times.

You may also stop when the kernel writes fewer records than your
buffer holds. That is always true at the end. The cursor is the better
test, because a directory whose length is an exact multiple of your
buffer would otherwise need one more call to discover it had ended.

## The records

A record is a fixed size, so the next one is always that many bytes on.
Each field is the width the thing it describes actually is, and it sits
where its own width wants it, so a field is one load and nothing has to
be shifted or masked. The sizes and the offsets are named in
`sdk/jab.inc`; a block record is `JAB_BLOCK_ENTRY` bytes and a romfs
record is `JAB_ROMFS_ENTRY`.

Fields are named after the thing they come from. A disk's capacity is
in sectors because that is virtio's unit, and its serial is virtio's
own device ID string. A romfs entry's `next` field carries the offset
of the following header with the mode in its low four bits, exactly as
the image on the disk stores it.

## The order of the arguments

The buffer comes first, the way a RISC-V load names its destination
first. What the call acts on comes next, then where in it to start,
then how much the buffer holds.

The SDK's macros load the argument registers from the highest down. A
value already in a low argument register can therefore be passed as a
later argument, which is what lets a paging loop hand `a1` straight
back in as the next cursor.
