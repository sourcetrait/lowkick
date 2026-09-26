//! Logs the SDL calls QEMU's window makes, one line each with a
//! microsecond timestamp, to the file the SDL_SHIM_LOG variable names,
//! when preloaded into QEMU with LD_PRELOAD. The jab probe reads the
//! log back to see how a program's flips reach the window: every
//! SDL_GL_MakeCurrent, which QEMU makes once per uploaded rectangle and
//! once per drawn frame, with the callers that led to it as module
//! plus offset; every SDL_GetWindowSize, which precedes a drawn frame;
//! every SDL_GL_SwapWindow, which ends one; and every SDL_PollEvent,
//! which the refresh timer makes. The real functions are found in
//! libSDL2 itself, since QEMU's SDL front end may be a module loaded
//! into its own scope, where RTLD_NEXT from a preload sees nothing.

use std::ffi::{c_char, c_int, c_void, CStr};
use std::io::Write;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

#[repr(C)]
struct DlInfo {
    dli_fname: *const c_char,
    dli_fbase: *mut c_void,
    dli_sname: *const c_char,
    dli_saddr: *mut c_void,
}

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dladdr(addr: *const c_void, info: *mut DlInfo) -> c_int;
    fn backtrace(buffer: *mut *mut c_void, size: c_int) -> c_int;
}

const RTLD_LAZY: c_int = 1;

static LOG: Mutex<Option<std::fs::File>> = Mutex::new(None);

/// Appends one line, the time since the epoch in seconds and
/// microseconds then the text, to the log; nothing when SDL_SHIM_LOG is
/// unset or the file cannot be opened.
fn log(what: &str) {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    let mut guard = match LOG.lock() {
        Ok(guard) => guard,
        Err(_) => return,
    };
    if guard.is_none() {
        if let Ok(path) = std::env::var("SDL_SHIM_LOG") {
            *guard = std::fs::OpenOptions::new().create(true).append(true).open(path).ok();
        }
    }
    if let Some(file) = guard.as_mut() {
        let _ = writeln!(file, "{}.{:06} {}", now.as_secs(), now.subsec_micros(), what);
    }
}

/// The real SDL function of that name, from libSDL2.
unsafe fn real(symbol: &[u8]) -> *mut c_void {
    let lib = dlopen(b"libSDL2-2.0.so.0\0".as_ptr() as *const c_char, RTLD_LAZY);
    if lib.is_null() {
        log("libSDL2 not found");
        std::process::abort();
    }
    let function = dlsym(lib, symbol.as_ptr() as *const c_char);
    if function.is_null() {
        log("symbol not found");
        std::process::abort();
    }
    function
}

/// The callers of the hooked function, four frames up from it, each as
/// the module's file name plus the offset into it, and in parentheses
/// the nearest exported symbol below the address with the distance to
/// it, when the loader knows one.
unsafe fn callers() -> String {
    let mut frames: [*mut c_void; 8] = [std::ptr::null_mut(); 8];
    let count = backtrace(frames.as_mut_ptr(), 8) as usize;
    let mut out = String::new();
    for frame in frames.iter().take(count).skip(2).take(4) {
        let mut info = DlInfo {
            dli_fname: std::ptr::null(),
            dli_fbase: std::ptr::null_mut(),
            dli_sname: std::ptr::null(),
            dli_saddr: std::ptr::null_mut(),
        };
        if dladdr(*frame, &mut info) != 0 && !info.dli_fname.is_null() {
            let name = CStr::from_ptr(info.dli_fname).to_string_lossy();
            let base = name.rsplit('/').next().unwrap_or("").to_string();
            let offset = (*frame as usize).wrapping_sub(info.dli_fbase as usize);
            if info.dli_sname.is_null() {
                out.push_str(&format!(" {}+{:x}", base, offset));
            } else {
                let symbol = CStr::from_ptr(info.dli_sname).to_string_lossy();
                let delta = (*frame as usize).wrapping_sub(info.dli_saddr as usize);
                out.push_str(&format!(" {}+{:x}({}+{:x})", base, offset, symbol, delta));
            }
        } else {
            out.push_str(&format!(" ?+{:x}", *frame as usize));
        }
    }
    out
}

type MakeCurrent = unsafe extern "C" fn(*mut c_void, *mut c_void) -> c_int;
type Swap = unsafe extern "C" fn(*mut c_void);
type WindowSize = unsafe extern "C" fn(*mut c_void, *mut c_int, *mut c_int);
type Poll = unsafe extern "C" fn(*mut c_void) -> c_int;

#[no_mangle]
pub unsafe extern "C" fn SDL_GL_MakeCurrent(window: *mut c_void, context: *mut c_void) -> c_int {
    let from = callers();
    log(&format!("make_current{}", from));
    let function: MakeCurrent = std::mem::transmute(real(b"SDL_GL_MakeCurrent\0"));
    function(window, context)
}

#[no_mangle]
pub unsafe extern "C" fn SDL_GL_SwapWindow(window: *mut c_void) {
    log("swap");
    let function: Swap = std::mem::transmute(real(b"SDL_GL_SwapWindow\0"));
    function(window)
}

#[no_mangle]
pub unsafe extern "C" fn SDL_GetWindowSize(window: *mut c_void, width: *mut c_int, height: *mut c_int) {
    log("size");
    let function: WindowSize = std::mem::transmute(real(b"SDL_GetWindowSize\0"));
    function(window, width, height)
}

#[no_mangle]
pub unsafe extern "C" fn SDL_PollEvent(event: *mut c_void) -> c_int {
    log("poll");
    let function: Poll = std::mem::transmute(real(b"SDL_PollEvent\0"));
    function(event)
}
