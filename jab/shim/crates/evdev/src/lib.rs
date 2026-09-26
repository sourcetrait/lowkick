//! Answers QEMU's evdev ioctls for a fifo, so a test attaches a gamepad
//! to `virtio-input-host-device` with no device on the host. Preloaded
//! into QEMU with LD_PRELOAD, it interposes `ioctl` and `write`,
//! recognises the fd whose file is the fifo named by EVDEV_SHIM_FIFO,
//! and answers for that fd as the reference pad, an 8BitDo Ultimate:
//! the version, the grab, the name and the id, the event bitmaps, and
//! each axis's absinfo. The events themselves reach QEMU through the
//! fifo, written by whoever plays them as 24-byte input_event records.
//! A write QEMU makes into the fd, a guest status event echoed to the
//! device, is swallowed, since on a fifo opened read-write it would come
//! back as input. Every other fd passes straight through to libc.

use std::ffi::{c_char, c_int, c_ulong, c_void};
use std::fs::File;
use std::mem::ManuallyDrop;
use std::os::fd::FromRawFd;
use std::os::unix::fs::MetadataExt;
use std::sync::OnceLock;

unsafe extern "C" {
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn __errno_location() -> *mut c_int;
}

/// glibc's handle for the next definition of a symbol after this one.
const RTLD_NEXT: *mut c_void = -1isize as *mut c_void;
const ENOTTY: c_int = 25;

type Ioctl = unsafe extern "C" fn(c_int, c_ulong, ...) -> c_int;
type Write = unsafe extern "C" fn(c_int, *const c_void, usize) -> isize;

static REAL_IOCTL: OnceLock<Ioctl> = OnceLock::new();
static REAL_WRITE: OnceLock<Write> = OnceLock::new();
/// The fifo's device and inode, or none when EVDEV_SHIM_FIFO is unset
/// or names nothing.
static FIFO: OnceLock<Option<(u64, u64)>> = OnceLock::new();

const EVDEV_VERSION: u32 = 0x010001;
const NAME: &[u8] = b"8BitDo Ultimate\0";
const BUS: u16 = 5;
const VENDOR: u16 = 0x2dc8;
const PRODUCT: u16 = 0x301b;
const VERSION: u16 = 1;

const EV_SYN: usize = 0x00;
const EV_KEY: usize = 0x01;
const EV_ABS: usize = 0x03;
const EV_MSC: usize = 0x04;
const BTN_GAMEPAD: usize = 0x130;
const BTN_LAST: usize = 0x13f;
const MSC_SCAN: usize = 0x04;
const ABS_X: usize = 0x00;
const ABS_Y: usize = 0x01;
const ABS_Z: usize = 0x02;
const ABS_RZ: usize = 0x05;
const ABS_GAS: usize = 0x09;
const ABS_BRAKE: usize = 0x0a;
const ABS_HAT0X: usize = 0x10;
const ABS_HAT0Y: usize = 0x11;

/// The ioctl command byte, the type being 'E' throughout.
const IOC_TYPE_EVDEV: u64 = 0x45;
const IOC_VERSION: u64 = 0x01;
const IOC_ID: u64 = 0x02;
const IOC_NAME: u64 = 0x06;
const IOC_PROP: u64 = 0x09;
const IOC_BIT: u64 = 0x20;
const IOC_ABS: u64 = 0x40;
const IOC_GRAB: u64 = 0x90;

/// The absinfo of an axis the pad has, in the fields' order: value,
/// min, max, fuzz, flat, resolution; none for an axis it lacks.
fn absinfo(axis: usize) -> Option<[i32; 6]> {
    match axis {
        ABS_X | ABS_Y | ABS_Z => Some([127, 0, 255, 0, 15, 0]),
        ABS_RZ => Some([127, 0, 255, 0, 15, 46]),
        ABS_GAS | ABS_BRAKE => Some([0, 0, 255, 0, 15, 0]),
        ABS_HAT0X | ABS_HAT0Y => Some([0, -1, 1, 0, 0, 0]),
        _ => None,
    }
}

/// The codes an event type can carry, as a bitmap of `size` bytes.
fn bitmap(ev: usize, size: usize) -> Vec<u8> {
    let mut bits = vec![0u8; size];
    let mut set = |code: usize| {
        if code / 8 < size {
            bits[code / 8] |= 1 << (code % 8);
        }
    };
    match ev {
        EV_SYN => {
            for t in [EV_SYN, EV_KEY, EV_ABS, EV_MSC] {
                set(t);
            }
        }
        EV_KEY => {
            for code in BTN_GAMEPAD..=BTN_LAST {
                set(code);
            }
        }
        EV_ABS => {
            for axis in [ABS_X, ABS_Y, ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE, ABS_HAT0X, ABS_HAT0Y] {
                set(axis);
            }
        }
        EV_MSC => set(MSC_SCAN),
        _ => {}
    }
    bits
}

/// Whether the fd is the fifo: its device and inode against the path's.
fn is_fifo(fd: c_int) -> bool {
    let fifo = FIFO.get_or_init(|| {
        let path = std::env::var_os("EVDEV_SHIM_FIFO")?;
        let meta = std::fs::metadata(path).ok()?;
        Some((meta.dev(), meta.ino()))
    });
    let Some((dev, ino)) = *fifo else { return false };
    if fd < 0 {
        return false;
    }
    let file = ManuallyDrop::new(unsafe { File::from_raw_fd(fd) });
    match file.metadata() {
        Ok(meta) => meta.dev() == dev && meta.ino() == ino,
        Err(_) => false,
    }
}

/// Copy `bytes` into the caller's buffer, at most `size` of them, and
/// report how many, as evdev does.
unsafe fn answer(arg: *mut c_void, size: usize, bytes: &[u8]) -> c_int {
    let n = bytes.len().min(size);
    if n > 0 && !arg.is_null() {
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), arg as *mut u8, n) };
    }
    n as c_int
}

/// The pad's answer to an evdev ioctl, or -1 with ENOTTY for one it
/// does not know.
unsafe fn evdev_ioctl(request: c_ulong, arg: *mut c_void) -> c_int {
    let request = request as u64;
    let size = ((request >> 16) & 0x3fff) as usize;
    let kind = (request >> 8) & 0xff;
    let nr = request & 0xff;
    if kind != IOC_TYPE_EVDEV {
        unsafe { *__errno_location() = ENOTTY };
        return -1;
    }
    match nr {
        IOC_VERSION => {
            unsafe { answer(arg, size, &EVDEV_VERSION.to_ne_bytes()) };
            0
        }
        IOC_ID => {
            let mut id = Vec::with_capacity(8);
            for field in [BUS, VENDOR, PRODUCT, VERSION] {
                id.extend_from_slice(&field.to_ne_bytes());
            }
            unsafe { answer(arg, size, &id) };
            0
        }
        IOC_NAME => unsafe { answer(arg, size, NAME) },
        IOC_PROP => unsafe { answer(arg, size, &vec![0u8; size]) },
        IOC_GRAB => 0,
        n if (IOC_BIT..IOC_ABS).contains(&n) => {
            let ev = (n - IOC_BIT) as usize;
            unsafe { answer(arg, size, &bitmap(ev, size)) }
        }
        n if (IOC_ABS..IOC_ABS + 0x40).contains(&n) => {
            let axis = (n - IOC_ABS) as usize;
            let info = absinfo(axis).unwrap_or([0; 6]);
            let mut bytes = Vec::with_capacity(24);
            for field in info {
                bytes.extend_from_slice(&field.to_ne_bytes());
            }
            unsafe { answer(arg, size, &bytes) };
            0
        }
        _ => {
            unsafe { *__errno_location() = ENOTTY };
            -1
        }
    }
}

/// libc's own function of that name, the next one after this library.
unsafe fn real(symbol: &[u8]) -> *mut c_void {
    let function = unsafe { dlsym(RTLD_NEXT, symbol.as_ptr() as *const c_char) };
    if function.is_null() {
        std::process::abort();
    }
    function
}

/// ioctl, taken as a fixed three-argument function: every evdev ioctl
/// and every other one QEMU makes passes its argument in the slot a
/// variadic call puts it in on this ABI.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ioctl(fd: c_int, request: c_ulong, arg: *mut c_void) -> c_int {
    if is_fifo(fd) {
        return unsafe { evdev_ioctl(request, arg) };
    }
    let function = REAL_IOCTL.get_or_init(|| unsafe { std::mem::transmute::<*mut c_void, Ioctl>(real(b"ioctl\0")) });
    unsafe { function(fd, request, arg) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn write(fd: c_int, buffer: *const c_void, count: usize) -> isize {
    if is_fifo(fd) {
        return count as isize;
    }
    let function = REAL_WRITE.get_or_init(|| unsafe { std::mem::transmute::<*mut c_void, Write>(real(b"write\0")) });
    unsafe { function(fd, buffer, count) }
}
