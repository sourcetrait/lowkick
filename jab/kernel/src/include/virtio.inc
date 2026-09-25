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
.set VIRTIO_ID_GPU, 16
.set VIRTIO_ID_INPUT, 18

# Status bits, written in order as the driver comes up
.set VIRTIO_STATUS_ACKNOWLEDGE, 1
.set VIRTIO_STATUS_DRIVER, 2
.set VIRTIO_STATUS_DRIVER_OK, 4
.set VIRTIO_STATUS_FEATURES_OK, 8

# The one feature the kernel offers: VIRTIO_F_VERSION_1, feature bit 32,
# which is bit 0 of feature word 1
.set VIRTIO_F_VERSION_1_WORD, 1
.set VIRTIO_F_VERSION_1_BIT, 1

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
# device can send
.set VIRTIO_INPUT_CFG_SELECT, 0
.set VIRTIO_INPUT_CFG_SUBSEL, 1
.set VIRTIO_INPUT_CFG_SIZE, 2
.set VIRTIO_INPUT_CFG_DATA, 8
.set VIRTIO_INPUT_CFG_EV_BITS, 0x11

# A virtio-input event, as Linux's: a type, a code, and a value
.set VIRTIO_INPUT_EVENT_TYPE, 0
.set VIRTIO_INPUT_EVENT_CODE, 2
.set VIRTIO_INPUT_EVENT_VALUE, 4
.set VIRTIO_INPUT_EVENT_SIZE, 8
.set EV_SYN, 0
.set EV_KEY, 1
