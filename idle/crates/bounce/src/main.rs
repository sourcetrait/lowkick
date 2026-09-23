use drm::buffer::{Buffer, DrmFourcc};
use drm::control::{self, connector, dumbbuffer::DumbBuffer, Device as ControlDevice, PageFlipFlags};
use std::fs::{File, OpenOptions};
use std::io::{self, ErrorKind};
use std::os::fd::{AsFd, BorrowedFd};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

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

fn render(
    card: &Card,
    buffer: &mut DumbBuffer,
    width: usize,
    height: usize,
    x: f32,
    y: f32,
    radius: i32,
) -> Result<(), Box<dyn std::error::Error>> {
    let pitch = buffer.pitch() as usize;
    let mut mapping = card.map_dumb_buffer(buffer)?;
    let pixels: &mut [u8] = mapping.as_mut();
    pixels.fill(0);

    // A simple frame makes it easy to see the four collision edges.
    for px in 0..width {
        pixel(pixels, pitch, px, 0, 0x0038_5575);
        pixel(pixels, pitch, px, height - 1, 0x0038_5575);
    }
    for py in 0..height {
        pixel(pixels, pitch, 0, py, 0x0038_5575);
        pixel(pixels, pitch, width - 1, py, 0x0038_5575);
    }

    let cx = x.round() as i32;
    let cy = y.round() as i32;
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let distance = dx * dx + dy * dy;
            if distance > radius * radius {
                continue;
            }
            let px = cx + dx;
            let py = cy + dy;
            if px <= 0 || py <= 0 || px >= width as i32 - 1 || py >= height as i32 - 1 {
                continue;
            }
            let color = if distance > (radius - 3) * (radius - 3) {
                0x00ff_a32b
            } else if dx < -radius / 4 && dy < -radius / 4 {
                0x00ff_f8d0
            } else {
                0x00f0_5730
            };
            pixel(pixels, pitch, px as usize, py as usize, color);
        }
    }
    Ok(())
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
    let mode = *connector
        .modes()
        .first()
        .ok_or_else(|| io::Error::new(ErrorKind::NotFound, "connector has no display modes"))?;
    let crtc = *resources
        .crtcs()
        .first()
        .ok_or_else(|| io::Error::new(ErrorKind::NotFound, "no DRM CRTC"))?;
    let previous = card.get_crtc(crtc)?;
    let (display_width, display_height) = mode.size();
    let (width, height) = (usize::from(display_width), usize::from(display_height));
    if width < 64 || height < 64 {
        return Err(io::Error::new(ErrorKind::InvalidData, "display is too small").into());
    }

    let mut buffers = Vec::with_capacity(2);
    for _ in 0..2 {
        let buffer = card.create_dumb_buffer(
            (width as u32, height as u32),
            DrmFourcc::Xrgb8888,
            32,
        )?;
        let framebuffer = card.add_framebuffer(&buffer, 24, 32)?;
        buffers.push((buffer, framebuffer));
    }

    let radius = (width.min(height) as i32 / 10).clamp(10, 32);
    let (mut x, mut y) = (width as f32 / 2.0, height as f32 / 2.0);
    let (mut vx, mut vy) = (240.0f32, 170.0f32);
    render(&card, &mut buffers[0].0, width, height, x, y, radius)?;
    card.set_crtc(crtc, Some(buffers[0].1), (0, 0), &[connector.handle()], Some(mode))?;

    // The shell stays on the serial console; pressing Enter there ends the animation.
    println!("Bouncing ball on {device} at {width}x{height}. Press Enter to stop.");
    let (stop_sender, stop_receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut line = String::new();
        let _ = io::stdin().read_line(&mut line);
        let _ = stop_sender.send(());
    });

    let mut front = 0usize;
    let mut last = Instant::now();
    while stop_receiver.try_recv().is_err() {
        let frame_start = Instant::now();
        let dt = frame_start.duration_since(last).as_secs_f32().min(0.1);
        last = frame_start;
        x += vx * dt;
        y += vy * dt;
        let (min_x, max_x) = (radius as f32 + 1.0, width as f32 - radius as f32 - 2.0);
        let (min_y, max_y) = (radius as f32 + 1.0, height as f32 - radius as f32 - 2.0);
        if x < min_x {
            x = min_x;
            vx = vx.abs();
        } else if x > max_x {
            x = max_x;
            vx = -vx.abs();
        }
        if y < min_y {
            y = min_y;
            vy = vy.abs();
        } else if y > max_y {
            y = max_y;
            vy = -vy.abs();
        }

        let back = 1 - front;
        render(&card, &mut buffers[back].0, width, height, x, y, radius)?;
        card.page_flip(crtc, buffers[back].1, PageFlipFlags::EVENT, None)?;
        while !card
            .receive_events()?
            .any(|event| matches!(event, control::Event::PageFlip(_)))
        {}
        front = back;
        thread::sleep(Duration::from_millis(16).saturating_sub(frame_start.elapsed()));
    }

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
    for (buffer, framebuffer) in buffers {
        card.destroy_framebuffer(framebuffer)?;
        card.destroy_dumb_buffer(buffer)?;
    }
    Ok(())
}
