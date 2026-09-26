# jab_pad.inc: what the pad's calls speak, evdev's own names
# (input-event-codes.h): the event types jab.pad.input reports, the
# gamepad's key codes, and the axis codes that index a state record's
# axes. Included by jab.inc.

# The event types a pad delivers
.set JAB_EV_KEY, 1
.set JAB_EV_ABS, 3

# The gamepad's keys, BTN_GAMEPAD on; a key's bit in a state record's
# keys is its code less JAB_BTN_GAMEPAD
.set JAB_BTN_GAMEPAD, 304
.set JAB_BTN_SOUTH, 304
.set JAB_BTN_EAST, 305
.set JAB_BTN_C, 306
.set JAB_BTN_NORTH, 307
.set JAB_BTN_WEST, 308
.set JAB_BTN_Z, 309
.set JAB_BTN_TL, 310
.set JAB_BTN_TR, 311
.set JAB_BTN_TL2, 312
.set JAB_BTN_TR2, 313
.set JAB_BTN_SELECT, 314
.set JAB_BTN_START, 315
.set JAB_BTN_MODE, 316
.set JAB_BTN_THUMBL, 317
.set JAB_BTN_THUMBR, 318

# The axes, each the index of its entry in a state record's axes
.set JAB_ABS_X, 0
.set JAB_ABS_Y, 1
.set JAB_ABS_Z, 2
.set JAB_ABS_RX, 3
.set JAB_ABS_RY, 4
.set JAB_ABS_RZ, 5
.set JAB_ABS_GAS, 9
.set JAB_ABS_BRAKE, 10
.set JAB_ABS_HAT0X, 16
.set JAB_ABS_HAT0Y, 17
