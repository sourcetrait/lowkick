# LowKick
> REIN HUMAN

LowKick is a Virtual System suite.

It defines a set of conservative virtual system specifications that roughly
follow current trends in affordable single-board computers.

Its flagship system spec is the self-named LowKick system.

Primary end-use is oriented towards hosting systems via QEMU on modern
Linux, MacOS, and Windows.

Secondary end-use is oriented towards hosting systems on bare single-board
computers.

Intended usage targets Appliance (home, office, industrial) and Entertainment.

Appliance usage targets hardware Panels; 8-10" touchscreens with an SBC (Linux)
attached, that are either mounted or on a desk stand.

Entertainment usage targets a gamepad + monitor configuration:
1. Desktop systems running QEMU (Linux, MacOS, Windows)
2. SBCs connected to a TV (Linux)
3. Panels (Linux)
4. Dedicated entertainment computers (Linux) connected to a TV, running QEMU

QEMU guest systems operate on Fedora CoreOS.
Within the guest, Podman containers run apps, operating on Fedora Minimal.

One application runs at a time and interacts directly with system devices.

Applications are written in Rust and are relatively low-level:
- Graphic rendering is direct, via Linux DRM.
- Gamepad interaction is handled via GilRs. 
- EGUI with a DRM backend handles any user interfaces throughout.

