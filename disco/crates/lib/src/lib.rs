//! What the expected devices are for LowKick's tools and launchers,
//! answered blind: today the gamepad, one record or none, as pretty
//! NUON. gilrs enumerates the pads the host knows about; the expected
//! one is the first connected pad with a known mapping, else the first
//! connected. On Linux its evdev path is what QEMU's host-input device
//! takes; elsewhere the path is null and the name still tells a
//! launcher what is there.

use gilrs::{Gilrs, MappingSource};

/// The expected gamepad.
struct Gamepad {
    /// The device's own name, as the OS reports it.
    name: String,
    /// Its evdev path on Linux; none elsewhere.
    path: Option<String>,
    vendor: Option<u16>,
    product: Option<u16>,
}

/// Discover, and say what was found as one pretty NUON record:
/// `{ gamepad: { name, path, vendor, product } }`, or `{ gamepad: null }`.
pub fn discover() -> String {
    match expected_gamepad() {
        Some(pad) => format!(
            "{{\n  gamepad: {{\n    name: {},\n    path: {},\n    vendor: {},\n    product: {}\n  }}\n}}",
            quoted(&pad.name),
            pad.path.as_deref().map(quoted).unwrap_or_else(|| "null".to_string()),
            number(pad.vendor),
            number(pad.product),
        ),
        None => "{\n  gamepad: null\n}".to_string(),
    }
}

/// A NUON string: double-quoted, with the quote and the backslash
/// escaped.
fn quoted(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

/// A NUON number, or null.
fn number(value: Option<u16>) -> String {
    match value {
        Some(number) => number.to_string(),
        None => "null".to_string(),
    }
}

/// The first connected pad with a known mapping, else the first
/// connected; none when gilrs finds nothing or cannot start.
fn expected_gamepad() -> Option<Gamepad> {
    let gilrs = match Gilrs::new() {
        Ok(gilrs) => gilrs,
        Err(gilrs::Error::NotImplemented(gilrs)) => gilrs,
        Err(_) => return None,
    };
    let connected: Vec<_> = gilrs.gamepads().filter(|(_, pad)| pad.is_connected()).collect();
    let (_, pad) = connected
        .iter()
        .find(|(_, pad)| pad.mapping_source() != MappingSource::None)
        .or_else(|| connected.first())?;
    Some(Gamepad {
        name: pad.os_name().to_string(),
        path: device_path(pad),
        vendor: pad.vendor_id(),
        product: pad.product_id(),
    })
}

#[cfg(target_os = "linux")]
fn device_path(pad: &gilrs::Gamepad) -> Option<String> {
    use gilrs::LinuxGamepadExt;
    Some(pad.devpath().to_string_lossy().into_owned())
}

#[cfg(not(target_os = "linux"))]
fn device_path(_pad: &gilrs::Gamepad) -> Option<String> {
    None
}
