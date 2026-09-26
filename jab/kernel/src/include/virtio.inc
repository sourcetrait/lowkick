# virtio.inc: virtio over mmio, version 2, and the virtio-gpu and
# virtio-input pieces the kernel drives the display and the keyboard
# with, as the virtio 1.3 specification lays them out. Offsets are
# bytes; registers are 32 bits wide.

# The transport's registers
.set VIRTIO_MMIO_MAGIC_VALUE, 0x000
.set VIRTIO_MMIO_VERSION, 0x004
.set VIRTIO_MMIO_DEVICE_ID, 0x008
.set VIRTIO_MMIO_DEVICE_FEATURES, 0x010
.set VIRTIO_MMIO_DEVICE_FEATURES_SEL, 0x014
.set VIRTIO_MMIO_DRIVER_FEATURES, 0x020
.set VIRTIO_MMIO_DRIVER_FEATURES_SEL, 0x024
.set VIRTIO_MMIO_QUEUE_SEL, 0x030
.set VIRTIO_MMIO_QUEUE_NUM_MAX, 0x034
.set VIRTIO_MMIO_QUEUE_NUM, 0x038
.set VIRTIO_MMIO_QUEUE_READY, 0x044
.set VIRTIO_MMIO_QUEUE_NOTIFY, 0x050
.set VIRTIO_MMIO_INTERRUPT_STATUS, 0x060
.set VIRTIO_MMIO_INTERRUPT_ACK, 0x064
.set VIRTIO_MMIO_STATUS, 0x070
.set VIRTIO_MMIO_QUEUE_DESC_LOW, 0x080
.set VIRTIO_MMIO_QUEUE_DESC_HIGH, 0x084
.set VIRTIO_MMIO_QUEUE_DRIVER_LOW, 0x090
.set VIRTIO_MMIO_QUEUE_DRIVER_HIGH, 0x094
.set VIRTIO_MMIO_QUEUE_DEVICE_LOW, 0x0a0
.set VIRTIO_MMIO_QUEUE_DEVICE_HIGH, 0x0a4
.set VIRTIO_MMIO_CONFIG, 0x100

# What a transport says about itself: "virt" as a little-endian word,
# version 2 for a modern transport, and the device id it carries
.set VIRTIO_MAGIC, 0x74726976
.set VIRTIO_VERSION_MODERN, 2
.set VIRTIO_ID_BLOCK, 2
.set VIRTIO_ID_CONSOLE, 3
.set VIRTIO_ID_GPU, 16
.set VIRTIO_ID_INPUT, 18

# Status bits, written in order as the driver comes up
.set VIRTIO_STATUS_ACKNOWLEDGE, 1
.set VIRTIO_STATUS_DRIVER, 2
.set VIRTIO_STATUS_DRIVER_OK, 4
.set VIRTIO_STATUS_FEATURES_OK, 8

# The feature the kernel offers every device: VIRTIO_F_VERSION_1,
# feature bit 32, which is bit 0 of feature word 1. A device's own
# features sit in word 0 and are offered beside it.
.set VIRTIO_F_VERSION_1_WORD, 1
.set VIRTIO_F_VERSION_1_BIT, 1

# virtio-console, which QEMU calls virtio-serial: with its multiport
# feature the device carries a port per channel, queues 2 and 3 carry
# control messages (the device's to the kernel, the kernel's to the
# device), and port n receives on queue 2n+2 and transmits on 2n+3. A
# control message is a port id, an event, and a value; the device names
# each port it carries once told the kernel is ready, and a port carries
# bytes once the kernel has answered for it and opened it.
.set VIRTIO_CONSOLE_F_MULTIPORT_BIT, (1 << 1)
.set VIRTIO_CONSOLE_CONTROL_RX_QUEUE, 2
.set VIRTIO_CONSOLE_CONTROL_TX_QUEUE, 3
.set VIRTIO_CONSOLE_CONTROL_ID, 0
.set VIRTIO_CONSOLE_CONTROL_EVENT, 4
.set VIRTIO_CONSOLE_CONTROL_VALUE, 6
.set VIRTIO_CONSOLE_CONTROL_SIZE, 8
.set VIRTIO_CONSOLE_DEVICE_READY, 0
.set VIRTIO_CONSOLE_PORT_ADD, 1
.set VIRTIO_CONSOLE_PORT_REMOVE, 2
.set VIRTIO_CONSOLE_PORT_READY, 3
.set VIRTIO_CONSOLE_CONSOLE_PORT, 4
.set VIRTIO_CONSOLE_RESIZE, 5
.set VIRTIO_CONSOLE_PORT_OPEN, 6
.set VIRTIO_CONSOLE_PORT_NAME, 7

# A split virtqueue of VIRTQ_SIZE entries: the descriptor table, the
# driver's (available) ring, and the device's (used) ring
.set VIRTQ_SIZE, 8
.set VIRTQ_DESC_ADDR, 0
.set VIRTQ_DESC_LEN, 8
.set VIRTQ_DESC_FLAGS, 12
.set VIRTQ_DESC_NEXT, 14
.set VIRTQ_DESC_SIZE, 16
.set VIRTQ_DESC_F_NEXT, 1
.set VIRTQ_DESC_F_WRITE, 2
.set VIRTQ_AVAIL_FLAGS, 0
.set VIRTQ_AVAIL_IDX, 2
.set VIRTQ_AVAIL_RING, 4
.set VIRTQ_USED_FLAGS, 0
.set VIRTQ_USED_IDX, 2
.set VIRTQ_USED_RING, 4
.set VIRTQ_USED_ELEM_ID, 0
.set VIRTQ_USED_ELEM_LEN, 4
.set VIRTQ_USED_ELEM_SIZE, 8

# The kernel's virtqueue record: the three rings, each at its alignment
# (16, 2, 4), then the last used index the kernel saw
.set VQ_DESC, 0
.set VQ_AVAIL, (VQ_DESC + VIRTQ_SIZE * VIRTQ_DESC_SIZE)
.set VQ_USED, (VQ_AVAIL + 32)
.set VQ_LAST_USED, (VQ_USED + 80)
.set VQ_BYTES, (VQ_LAST_USED + 8)
# An array of these needs every record at the descriptor table's own
# alignment, so its stride is the record rounded up to 16.
.set VQ_STRIDE, (((VQ_BYTES + 15) / 16) * 16)

# The GPU's control queue is the one queue with many commands in flight
# at once, a rectangle list's transfers and flushes, so it has a record
# of its own with GPUQ_SIZE entries: the rings at the same alignments,
# the last used index, and how many chains are pending in a batch.
.set GPUQ_SIZE, 64
.set GPUQ_DESC, 0
.set GPUQ_AVAIL, (GPUQ_DESC + GPUQ_SIZE * VIRTQ_DESC_SIZE)
.set GPUQ_USED, (GPUQ_AVAIL + ((6 + 2 * GPUQ_SIZE + 3) / 4) * 4)
.set GPUQ_LAST_USED, (GPUQ_USED + ((6 + 8 * GPUQ_SIZE + 7) / 8) * 8)
.set GPUQ_PENDING, (GPUQ_LAST_USED + 8)
.set GPUQ_BYTES, (GPUQ_PENDING + 8)
# a batch is at most half the queue, two descriptors a chain
.set GPUQ_CHAINS, (GPUQ_SIZE / 2)

# The virtio-gpu control header every command and response starts with
.set VIRTIO_GPU_HDR_TYPE, 0
.set VIRTIO_GPU_HDR_FLAGS, 4
.set VIRTIO_GPU_HDR_FENCE_ID, 8
.set VIRTIO_GPU_HDR_CTX_ID, 16
.set VIRTIO_GPU_HDR_SIZE, 24

# Commands, and the responses that say they went through
.set VIRTIO_GPU_CMD_GET_DISPLAY_INFO, 0x0100
.set VIRTIO_GPU_CMD_RESOURCE_CREATE_2D, 0x0101
.set VIRTIO_GPU_CMD_SET_SCANOUT, 0x0103
.set VIRTIO_GPU_CMD_RESOURCE_FLUSH, 0x0104
.set VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D, 0x0105
.set VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING, 0x0106
.set VIRTIO_GPU_RESP_OK_NODATA, 0x1100
.set VIRTIO_GPU_RESP_OK_DISPLAY_INFO, 0x1101

# A rectangle: x, y, width, height
.set VIRTIO_GPU_RECT_X, 0
.set VIRTIO_GPU_RECT_Y, 4
.set VIRTIO_GPU_RECT_WIDTH, 8
.set VIRTIO_GPU_RECT_HEIGHT, 12

# Each command's fields after the header, and its whole size
.set VIRTIO_GPU_CREATE_2D_RESOURCE_ID, 24
.set VIRTIO_GPU_CREATE_2D_FORMAT, 28
.set VIRTIO_GPU_CREATE_2D_WIDTH, 32
.set VIRTIO_GPU_CREATE_2D_HEIGHT, 36
.set VIRTIO_GPU_CREATE_2D_SIZE, 40
.set VIRTIO_GPU_ATTACH_RESOURCE_ID, 24
.set VIRTIO_GPU_ATTACH_NR_ENTRIES, 28
.set VIRTIO_GPU_ATTACH_ENTRY_ADDR, 32
.set VIRTIO_GPU_ATTACH_ENTRY_LENGTH, 40
.set VIRTIO_GPU_ATTACH_SIZE, 48
.set VIRTIO_GPU_SCANOUT_RECT, 24
.set VIRTIO_GPU_SCANOUT_ID, 40
.set VIRTIO_GPU_SCANOUT_RESOURCE_ID, 44
.set VIRTIO_GPU_SCANOUT_SIZE, 48
.set VIRTIO_GPU_TRANSFER_RECT, 24
.set VIRTIO_GPU_TRANSFER_OFFSET, 40
.set VIRTIO_GPU_TRANSFER_RESOURCE_ID, 48
.set VIRTIO_GPU_TRANSFER_SIZE, 56
.set VIRTIO_GPU_FLUSH_RECT, 24
.set VIRTIO_GPU_FLUSH_RESOURCE_ID, 40
.set VIRTIO_GPU_FLUSH_SIZE, 48

# The display info response: the header, then sixteen modes of a
# rectangle, an enabled word, and a flags word
.set VIRTIO_GPU_DISPLAY_INFO_MODES, 24
.set VIRTIO_GPU_DISPLAY_ONE_ENABLED, 16
.set VIRTIO_GPU_DISPLAY_ONE_SIZE, 24
.set VIRTIO_GPU_DISPLAY_INFO_SIZE, (24 + 16 * 24)

# The framebuffer's format: bytes blue, green, red, unused
.set VIRTIO_GPU_FORMAT_B8G8R8X8_UNORM, 2

# virtio-input's config: a select and a subselect byte pick what the
# payload at VIRTIO_INPUT_CFG_DATA describes, and size says how long it
# is; EV_BITS with an event type gives the bitmap of the codes the
# device can send, and ABS_INFO with an axis code its absinfo, five
# little-endian 32-bit fields: min, max, fuzz, flat, resolution
.set VIRTIO_INPUT_CFG_SELECT, 0
.set VIRTIO_INPUT_CFG_SUBSEL, 1
.set VIRTIO_INPUT_CFG_SIZE, 2
.set VIRTIO_INPUT_CFG_DATA, 8
.set VIRTIO_INPUT_CFG_EV_BITS, 0x11
.set VIRTIO_INPUT_CFG_ABS_INFO, 0x12
.set VIRTIO_INPUT_ABS_MIN, 0
.set VIRTIO_INPUT_ABS_MAX, 4
.set VIRTIO_INPUT_ABS_FUZZ, 8
.set VIRTIO_INPUT_ABS_FLAT, 12
.set VIRTIO_INPUT_ABS_RES, 16
.set VIRTIO_INPUT_ABS_SIZE, 20

# The pad's event queue is the other wide one: the device fills a
# buffer per event, a pad sends several a report at over a hundred
# reports a second, and the kernel drains only when the program calls
# or waits, so PADQ_SIZE buffers stand offered. The record is the
# GPU's shape without a pending count.
.set PADQ_SIZE, 64
.set PADQ_DESC, 0
.set PADQ_AVAIL, (PADQ_DESC + PADQ_SIZE * VIRTQ_DESC_SIZE)
.set PADQ_USED, (PADQ_AVAIL + ((6 + 2 * PADQ_SIZE + 3) / 4) * 4)
.set PADQ_LAST_USED, (PADQ_USED + ((6 + 8 * PADQ_SIZE + 7) / 8) * 8)
.set PADQ_BYTES, (PADQ_LAST_USED + 8)

# virtio-blk: the capacity, in 512-byte sectors, opens the config space
# as a little-endian 64-bit value, read as two words since the transport
# takes config accesses of four bytes. A request is a header the device
# reads, the data, and a status byte the device writes, three
# descriptors chained; the type and the sector go in the header, and
# GET_ID answers with the device ID string QEMU takes from `serial=`.
.set VIRTIO_BLK_CFG_CAPACITY_LOW, 0
.set VIRTIO_BLK_CFG_CAPACITY_HIGH, 4
.set VIRTIO_BLK_ID_BYTES, 20
.set VIRTIO_BLK_T_IN, 0
.set VIRTIO_BLK_T_OUT, 1
.set VIRTIO_BLK_T_GET_ID, 8
.set VIRTIO_BLK_S_OK, 0
.set VIRTIO_BLK_REQ_TYPE, 0
.set VIRTIO_BLK_REQ_IOPRIO, 4
.set VIRTIO_BLK_REQ_SECTOR, 8
.set VIRTIO_BLK_REQ_SIZE, 16

# A virtio-input event, as Linux's: a type, a code, and a value
.set VIRTIO_INPUT_EVENT_TYPE, 0
.set VIRTIO_INPUT_EVENT_CODE, 2
.set VIRTIO_INPUT_EVENT_VALUE, 4
.set VIRTIO_INPUT_EVENT_SIZE, 8
.set EV_SYN, 0
.set EV_KEY, 1
.set EV_ABS, 3
.set EV_MSC, 4
