# Board support — what the real MB86H615 still needs

This directory holds the board-specific half of the port. Right now it contains
only what can be written without hardware: the users table, the kernel fragment
and the post-build hook.

**The files needed to boot on silicon do not exist yet, and none of them can be
derived from `gsat_firm.bin` alone.** That is not a limitation of the tooling —
the information is simply not present in a flash read-out.

## What the existing firmware tells us

Decoded from `gsat_firm.bin` (see `../../../notes/01-platform.md`):

| Property | Value |
|---|---|
| SoC | Fujitsu MB86H615 |
| Core | ARM1176JZF-S (ARMv6, MMU, VFP11) |
| Boot loader | `MB86H615 Flash Boot Loader` rev 5404, 2011-03-01, Fujitsu Semiconductor Europe |
| Boot media | P-Flash (parallel NOR), S-Flash (serial NOR), N-Flash (NAND) |
| Boot scheme | multiple CRC-validated slots + fallback loader |
| Flash size | 8 MiB total, image word-swapped (32-bit endianness) |
| Demod | Montage M88DS3103 (DVB-S2, I2C) |
| Front panel | FD650 LED driver (I2C, `MTR_FP_SCAN_MCU_FD650_MODE`) |
| Runtime | in-house RTOS, `mmu/src/drv_mmu_heap_bget.c`, bget allocator |
| HAL | `FAPI_*` modules: GPIO, I2C, UART, FLASH, TSD (demux), DESC, HDMI, SHELL, TTX, MV |

The presence of `FAPI_SHELL_MODULE_BASE` over `FAPI_UART_MODULE_BASE` means the
shipped firmware contains a **serial debug shell**. Getting at that is a far
cheaper route to a terminal on the box than any Linux port.

## Checklist — every item blocks a real boot

### 1. Boot ROM image format  ← hard blocker
The loader in flash is stage 2. Stage 1 is in mask ROM and accepts only images
with a Fujitsu header at Fujitsu-defined offsets.

- [ ] Locate the boot ROM entry point and its header expectation
- [ ] Determine whether the ROM reads NOR directly or expects a pre-copied image
- [ ] Recover checksum/CRC algorithm and any signature verification
- [ ] Confirm whether secure boot fuses are programmed (if yes: full stop)

Route: dump the boot ROM by executing from it under a debugger, or find the
Fujitsu "flash loader" documentation. Without this, no image of ours is loadable.

### 2. DDR / PLL / clock / pinmux init
- [ ] DDR controller base + timing table
- [ ] PLL registers and boot frequency
- [ ] Pinmux for UART, I2C, flash, video

Route: capture the existing loader's writes over JTAG at boot, or find the
Fujitsu reference "init" blob. This is typically 200–600 register writes.

### 3. Console UART
- [ ] Physical UART base address and IRQ (PL011-compatible? Fujitsu custom?)
- [ ] Baud rate / divisor and pin header location on the PCB

Route: probe the board with a USB-TTL adapter at 115200 8N1 on likely test pads;
the FAPI shell is the reward.

### 4. Interrupt controller and timers
- [ ] GIC or Fujitsu custom controller, base address, IRQ numbering
- [ ] System timer / watchdog base and frequency

### 5. Flash controller
- [ ] SPI or parallel NOR controller registers
- [ ] Slot table location and CRC parameters (the loader prints them)

### 6. Video / OSD / HDMI — optional for a headless build
- [ ] OSD framebuffer base and format
- [ ] Video decoder (proprietary, no public driver)
- [ ] HDMI/HDCP block

Skip entirely if the goal is a headless terminal box.

### 7. DVB-S2 front end — partially available
- [ ] I2C bus number and demod address on this board
- [ ] Tuner part number (the config string names `FUJITSU_W9_YINHE_2212`)
- [ ] LNB supply / DiSEqC GPIOs

Good news: mainline Linux has `drivers/media/dvb-frontends/m88ds3103.c` and
`m88ds3103_priv.h`. The demod driver exists; only the board wiring is unknown.

### 8. Front panel / IR
- [ ] FD650 I2C address and segment map
- [ ] IR receiver GPIO + protocol (NEC?)

Low risk, easy to write once the pins are known.

## Suggested order of attack

1. **UART shell first.** Open the box, find the serial pads, capture boot output.
   If `FAPI_SHELL` answers, you already have a root-ish terminal in the stock
   firmware — no Linux needed for most goals.
2. **JTAG second.** A boot-time trace gives you DDR/PLL/pinmux values, which is
   the single largest missing piece.
3. **Boot ROM third.** Only worth it once you can recover a bricked board.
4. **Linux last.** With 1–3 done, this tree's `linux.fragment` becomes a real
   board file instead of a QEMU stand-in.

## Flashing reality check

- The receiver's flash is 8 MiB. A kernel + minimal initramfs fits; a normal
  distro userland does not.
- Any write to the NOR needs a verified recovery path — either a second working
  slot, or an SPI clip/programmer with the original dump
  (`gsat_firm.bin`, SHA-256 `B292484B…2B1E89`) kept off-device.
- `gsat_firm.bin` is **word-swapped**. If you ever write it back, write the raw
  bytes exactly as dumped — do not write the `rev4` normalized copy.
