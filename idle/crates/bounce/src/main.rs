use drm::buffer::{Buffer, DrmFourcc};
use drm::control::{self, connector, Device as ControlDevice, PageFlipFlags};
use std::fs::{File, OpenOptions};
use std::io::{self, ErrorKind};
use std::os::fd::{AsFd, BorrowedFd};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

const TARGET_FPS: u32 = 30;

// drm-rs deliberately leaves device opening to the application.
struct Card(File);

impl AsFd for Card {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.0.as_fd()
    }
}

impl drm::Device for Card {}
impl ControlDevice for Card {}

fn pixel(bytes: &mut [u8], pitch: usize, x: usize, y: usize, rgb: u32) {
    let start = y * pitch + x * 4;
    bytes[start..start + 4].copy_from_slice(&rgb.to_ne_bytes());
}

#[derive(Clone, Copy)]
struct Rect {
    left: usize,
    top: usize,
    right: usize,
    bottom: usize,
}

fn ball_bounds(width: usize, height: usize, position: (f32, f32), radius: f32) -> Rect {
    let (x, y) = position;
    let extent = radius + 1.0;
    Rect {
        left: (x - extent).floor().max(0.0) as usize,
        top: (y - extent).floor().max(0.0) as usize,
        right: ((x + extent).ceil() as usize).min(width),
        bottom: ((y + extent).ceil() as usize).min(height),
    }
}

fn clear_rect(pixels: &mut [u8], pitch: usize, rect: Rect) {
    for py in rect.top..rect.bottom {
        let start = py * pitch + rect.left * 4;
        let end = py * pitch + rect.right * 4;
        pixels[start..end].fill(0);
    }
}

fn draw_ball(
    pixels: &mut [u8],
    pitch: usize,
    width: usize,
    height: usize,
    position: (f32, f32),
    radius: f32,
) -> Rect {
    let (x, y) = position;
    let bounds = ball_bounds(width, height, position, radius);
    let inner_squared = (radius - 0.5).powi(2);
    let outer_squared = (radius + 0.5).powi(2);
    for py in bounds.top..bounds.bottom {
        let dy = py as f32 - y;
        for px in bounds.left..bounds.right {
            let dx = px as f32 - x;
            let distance_squared = dx * dx + dy * dy;
            let red = if distance_squared <= inner_squared {
                255
            } else if distance_squared >= outer_squared {
                continue;
            } else {
                ((radius + 0.5 - distance_squared.sqrt()) * 255.0).round() as u32
            };
            pixel(pixels, pitch, px, py, red << 16);
        }
    }
    bounds
}

fn bounce_axis(start: f32, speed: f32, elapsed: f32, min: f32, max: f32) -> f32 {
    let span = max - min;
    let phase = (start - min + speed * elapsed).rem_euclid(2.0 * span);
    min + span - (phase - span).abs()
}

fn ball_position(
    origin: (f32, f32),
    speed: (f32, f32),
    elapsed: f32,
    min: (f32, f32),
    max: (f32, f32),
) -> (f32, f32) {
    (
        bounce_axis(origin.0, speed.0, elapsed, min.0, max.0),
        bounce_axis(origin.1, speed.1, elapsed, min.1, max.1),
    )
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let device = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "/dev/dri/card0".to_owned());
    let card = Card(OpenOptions::new().read(true).write(true).open(&device)?);
    let resources = card.resource_handles()?;
    let connector = resources
        .connectors()
        .iter()
        .filter_map(|&handle| card.get_connector(handle, true).ok())
        .find(|info| info.state() == connector::State::Connected)
        .ok_or_else(|| io::Error::new(ErrorKind::NotFound, "no connected DRM connector"))?;
    let mode = connector
        .modes()
        .iter()
        .copied()
        .find(|mode| mode.size() == (1920, 1080) && mode.vrefresh() == 60)
        .ok_or_else(|| io::Error::new(ErrorKind::NotFound, "1920x1080 @ 60 Hz mode unavailable"))?;
    let crtc = *resources
        .crtcs()
        .first()
        .ok_or_else(|| io::Error::new(ErrorKind::NotFound, "no DRM CRTC"))?;
    let previous = card.get_crtc(crtc)?;
    let (display_width, display_height) = mode.size();
    let (width, height) = (usize::from(display_width), usize::from(display_height));
    let refresh = mode.vrefresh();
    if refresh == 0 {
        return Err(
            io::Error::new(ErrorKind::InvalidData, "display mode has no refresh rate").into(),
        );
    }
    let frame_period = Duration::from_secs_f64(1.0 / f64::from(TARGET_FPS));
    let draw_period = Duration::from_secs_f64(1.0 / f64::from(refresh));
    if width < 64 || height < 64 {
        return Err(io::Error::new(ErrorKind::InvalidData, "display is too small").into());
    }

    let mut first_buffer =
        card.create_dumb_buffer((width as u32, height as u32), DrmFourcc::Xrgb8888, 32)?;
    let first_framebuffer = card.add_framebuffer(&first_buffer, 24, 32)?;
    let mut second_buffer =
        card.create_dumb_buffer((width as u32, height as u32), DrmFourcc::Xrgb8888, 32)?;
    let second_framebuffer = card.add_framebuffer(&second_buffer, 24, 32)?;
    let mut third_buffer =
        card.create_dumb_buffer((width as u32, height as u32), DrmFourcc::Xrgb8888, 32)?;
    let third_framebuffer = card.add_framebuffer(&third_buffer, 24, 32)?;
    let framebuffers = [first_framebuffer, second_framebuffer, third_framebuffer];
    let pitches = [
        first_buffer.pitch() as usize,
        second_buffer.pitch() as usize,
        third_buffer.pitch() as usize,
    ];
    let mut mappings = [
        card.map_dumb_buffer(&mut first_buffer)?,
        card.map_dumb_buffer(&mut second_buffer)?,
        card.map_dumb_buffer(&mut third_buffer)?,
    ];
    for mapping in &mut mappings {
        let pixels: &mut [u8] = mapping.as_mut();
        pixels.fill(0);
    }
    let mut previous_bounds = [None, None, None];

    let radius = (width.min(height) as f32 / 10.0).max(10.0);
    let origin: (f32, f32) = (width as f32 / 2.0, height as f32 / 2.0);
    let speed: (f32, f32) = (720.0, 510.0);
    let min = (radius + 1.0, radius + 1.0);
    let max = (width as f32 - radius - 2.0, height as f32 - radius - 2.0);
    previous_bounds[0] = Some(draw_ball(
        mappings[0].as_mut(),
        pitches[0],
        width,
        height,
        origin,
        radius,
    ));
    card.set_crtc(
        crtc,
        Some(framebuffers[0]),
        (0, 0),
        &[connector.handle()],
        Some(mode),
    )?;
    let started_at = Instant::now();

    // The shell stays on the serial console; pressing Enter there ends the animation.
    println!(
        "Bouncing ball on {device} at {width}x{height} @ {refresh} Hz (draw up to {refresh} fps, flip up to {TARGET_FPS} fps). Press Enter to stop."
    );
    let (stop_sender, stop_receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut line = String::new();
        let _ = io::stdin().read_line(&mut line);
        let _ = stop_sender.send(());
    });

    // A buffer becomes free only when a newer ready frame replaces it, or
    // after the flip event releases the previously displayed buffer.
    let (free_tx, free_rx) = mpsc::channel::<usize>();
    let (ready_tx, ready_rx) = mpsc::channel::<usize>();
    free_tx.send(1)?;
    free_tx.send(2)?;

    let (mappings, animation_result) = thread::scope(|scope| {
        let renderer = scope.spawn(move || {
            let mut mappings = mappings;
            let mut previous_bounds = previous_bounds;
            let mut next_draw = Instant::now();
            while let Ok(drawing) = free_rx.recv() {
                let wait = next_draw.saturating_duration_since(Instant::now());
                if !wait.is_zero() {
                    thread::sleep(wait);
                }
                let now = Instant::now();
                let elapsed = now.duration_since(started_at).as_secs_f32();
                let position: (f32, f32) = ball_position(origin, speed, elapsed, min, max);
                let pixels: &mut [u8] = mappings[drawing].as_mut();
                if let Some(bounds) = previous_bounds[drawing] {
                    clear_rect(pixels, pitches[drawing], bounds);
                }
                previous_bounds[drawing] = Some(draw_ball(
                    pixels,
                    pitches[drawing],
                    width,
                    height,
                    position,
                    radius,
                ));
                if ready_tx.send(drawing).is_err() {
                    break;
                }
                while next_draw <= Instant::now() {
                    next_draw += draw_period;
                }
            }
            mappings
        });

        let animation_result = (|| -> Result<(), Box<dyn std::error::Error>> {
            let mut displayed = 0usize;
            let mut next_flip = Instant::now() + frame_period;
            while stop_receiver.try_recv().is_err() {
                let wait = next_flip.saturating_duration_since(Instant::now());
                if !wait.is_zero() {
                    thread::sleep(wait);
                }
                if stop_receiver.try_recv().is_ok() {
                    break;
                }

                let mut ready = None;
                for completed in ready_rx.try_iter() {
                    if let Some(stale) = ready.replace(completed) {
                        free_tx.send(stale).map_err(|_| {
                            io::Error::new(ErrorKind::BrokenPipe, "renderer stopped")
                        })?;
                    }
                }
                if let Some(presenting) = ready {
                    card.page_flip(crtc, framebuffers[presenting], PageFlipFlags::EVENT, None)?;
                    while !card
                        .receive_events()?
                        .any(|event| matches!(event, control::Event::PageFlip(_)))
                    {
                    }
                    free_tx
                        .send(displayed)
                        .map_err(|_| io::Error::new(ErrorKind::BrokenPipe, "renderer stopped"))?;
                    displayed = presenting;
                }
                while next_flip <= Instant::now() {
                    next_flip += frame_period;
                }
            }
            Ok(())
        })();

        drop(ready_rx);
        drop(free_tx);
        let mappings = renderer.join().expect("renderer thread panicked");
        (mappings, animation_result)
    });

    if let (Some(old_buffer), Some(old_mode)) = (previous.framebuffer(), previous.mode()) {
        let _ = card.set_crtc(
            crtc,
            Some(old_buffer),
            previous.position(),
            &[connector.handle()],
            Some(old_mode),
        );
    } else {
        let _ = card.set_crtc(crtc, None, (0, 0), &[], None);
    }
    drop(mappings);
    card.destroy_framebuffer(first_framebuffer)?;
    card.destroy_dumb_buffer(first_buffer)?;
    card.destroy_framebuffer(second_framebuffer)?;
    card.destroy_dumb_buffer(second_buffer)?;
    card.destroy_framebuffer(third_framebuffer)?;
    card.destroy_dumb_buffer(third_buffer)?;
    animation_result?;
    Ok(())
}
