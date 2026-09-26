//! What the expected devices are for LowKick's tools and launchers,
//! answered blind: today the gamepad, one record or none, as pretty
//! NUON. gilrs enumerates the pads the host knows about; the expected
//! one is the first connected pad with a known mapping, else the first
//! connected. On Linux its evdev path is what QEMU's host-input device
//! takes; elsewhere the path is null and the name still tells a
//! launcher what is there.

use gilrs::{Gilrs, MappingSource};
use nu_protocol::engine::EngineState;
use nu_protocol::{Span, Value, record};
use nuon::{ToNuonConfig, ToStyle};

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
    let span = Span::unknown();
    let gamepad = match expected_gamepad() {
        Some(pad) => Value::record(
            record! {
                "name" => Value::string(pad.name, span),
                "path" => optional_string(pad.path, span),
                "vendor" => optional_int(pad.vendor, span),
                "product" => optional_int(pad.product, span),
            },
            span,
        ),
        None => Value::nothing(span),
    };
    let found = Value::record(record! { "gamepad" => gamepad }, span);
    let config = ToNuonConfig::default().style(ToStyle::Spaces(2)).span(Some(span));
    nuon::to_nuon(&EngineState::new(), &found, config).unwrap_or_else(|_| "{ gamepad: null }".to_string())
}

fn optional_string(value: Option<String>, span: Span) -> Value {
    match value {
        Some(text) => Value::string(text, span),
        None => Value::nothing(span),
    }
}

fn optional_int(value: Option<u16>, span: Span) -> Value {
    match value {
        Some(number) => Value::int(i64::from(number), span),
        None => Value::nothing(span),
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
