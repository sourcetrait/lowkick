use std::fs::{File, OpenOptions};
use std::os::unix::io::{AsFd, BorrowedFd};

use drm::buffer::{Buffer, DrmFourcc};
use drm::control::{connector, crtc, dumbbuffer::DumbBuffer, framebuffer,
                   Device as ControlDevice, PageFlipFlags};
use drm::Device;

struct Card(File);
impl AsFd for Card {
    fn as_fd(&self) -> BorrowedFd<'_> { self.0.as_fd() }
}
impl Device for Card {}
impl ControlDevice for Card {}

const BG:   u32 = 0xFF10_1018;
const BALL: u32 = 0xFFFF_5533;

struct Fb {
    db: DumbBuffer,
    fb: framebuffer::Handle,
}

fn main() {
    let card = Card(
        OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/dri/card0")
            .expect("open /dev/dri/card0"),
    );

    let res = card.resource_handles().expect("resource handles");

    let connector = res
        .connectors()
        .iter()
        .map(|&h| card.get_connector(h, true).expect("get_connector"))
        .find(|c| u32::from(c.handle()) == 40 && c.state() == connector::State::Connected)
        .or_else(|| {
            res.connectors()
                .iter()
                .map(|&h| card.get_connector(h, true).unwrap())
                .find(|c| c.state() == connector::State::Connected)
        })
        .expect("no connected connector");

    let &mode = connector
        .modes()
        .iter()
        .find(|m| {
            let (w, h) = m.size();
            w as u32 == 1920 && h as u32 == 1080
        })
        .or_else(|| connector.modes().iter().next())
        .expect("connector has no modes");

    let (sw, sh) = mode.size();
    let (w, h) = (sw as usize, sh as usize);
    eprintln!("rendering at {}x{}", w, h);

    let crtc: crtc::Handle = res
        .crtcs()
        .iter()
        .copied()
        .find(|c| u32::from(*c) == 39)
        .unwrap_or_else(|| *res.crtcs().first().expect("no crtc"));

    let mut bufs = [
        make_fb(&card, sw as u32, sh as u32),
        make_fb(&card, sw as u32, sh as u32),
    ];

    card.set_crtc(crtc, Some(bufs[0].fb), (0, 0), &[connector.handle()], Some(mode))
        .expect("set_crtc");

    let mut x = 200.0f32;
    let mut y = 200.0f32;
    let mut vx = 7.0f32;
    let mut vy = 5.0f32;
    let r = 90.0f32;

    let mut front = 0usize;

    loop {
        // ---- update ----
        x += vx;
        y += vy;
        if x - r < 0.0 { x = r; vx = -vx; }
        if x + r > w as f32 { x = w as f32 - r; vx = -vx; }
        if y - r < 0.0 { y = r; vy = -vy; }
        if y + r > h as f32 { y = h as f32 - r; vy = -vy; }

        // ---- render into back buffer ----
        let back = 1 - front;
        {
            let mut map = card
                .map_dumb_buffer(&mut bufs[back].db)
                .expect("map_dumb_buffer");
            let dst: &mut [u8] = map.as_mut();
            let pitch = dst.len() / h;

            let bg = BG.to_le_bytes();
            for row in dst.chunks_mut(pitch) {
                for px in row[..w * 4].chunks_mut(4) {
                    px.copy_from_slice(&bg);
                }
            }

            let r2 = r * r;
            let x0 = (x - r).floor().max(0.0) as usize;
            let x1 = (x + r).ceil().min(w as f32) as usize;
            let y0 = (y - r).floor().max(0.0) as usize;
            let y1 = (y + r).ceil().min(h as f32) as usize;
            let ball = BALL.to_le_bytes();
            for py in y0..y1 {
                let row = &mut dst[py * pitch..py * pitch + w * 4];
                for px in x0..x1 {
                    let dx = px as f32 + 0.5 - x;
                    let dy = py as f32 + 0.5 - y;
                    if dx * dx + dy * dy <= r2 {
                        let o = px * 4;
                        row[o..o + 4].copy_from_slice(&ball);
                    }
                }
            }
        } // map drops -> flush

        // ---- present (blocks until vblank: paces at 60, CPU idle between) ----
        card.page_flip(crtc, bufs[back].fb, PageFlipFlags::EVENT, None)
            .expect("page_flip");
        let _ = card.receive_events();

        front = back;
    }
}

fn make_fb(card: &Card, w: u32, h: u32) -> Fb {
    let db = card
        .create_dumb_buffer((w, h), DrmFourcc::Xrgb8888, 32)
        .expect("create_dumb_buffer");
    let fb = card.add_framebuffer(&db, 24, 32).expect("add_framebuffer");
    Fb { db, fb }
}
