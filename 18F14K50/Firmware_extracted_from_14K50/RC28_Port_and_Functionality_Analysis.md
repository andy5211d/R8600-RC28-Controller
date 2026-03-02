# Icom RC-28 PIC18F Firmware — Port Usage and Functionality Analysis

## Device Identification Revision

Previous analysis assumed the target was a **PIC18F14K50**, but the firmware
contradicts this. The instruction at buffer offset `0x027E`:

```
BTFSS PORTB,2       ; test RB2
```

...and the masking operation:

```
MOVF PORTB,W
ANDLW 0x78          ; 0111 1000 → uses RB3, RB4, RB5, RB6
```

Both reference pins (RB2–RB6) that **do not exist on the PIC18F14K50**, which only
exposes RB4–RB7. The firmware is consistent with a **PIC18F25K50** or **PIC18F2553**
— 28-pin parts with a full 8-bit PORTB (RB0–RB7), native USB, and the same 16 KB
flash constraint.

---

## Port Register Configuration Summary

All analogue functions are disabled at startup (`CLRF ANSEL`), making all port pins
digital. The TRIS direction registers are set by the bootloader before handing off,
so only the LAT and WPU init values in the application code are visible here.

| Register | Value set | Meaning |
|---|---|---|
| `ANSEL` | `0x00` | All PORTA pins digital |
| `LATB` | `0x01` | RB0 driven high at startup |
| `LATC` | `0x01` | RC0 driven high at startup |
| `LATA` | `0x00` | All PORTA outputs low at startup |
| `WPUA` | `0x02` (bit 1) | RA1 has internal weak pull-up → input |
| `WPUB` | `0x01` (bit 0) | RB0 has internal weak pull-up |
| `IOCB` | `0x28` (bits 3,5) | Interrupt-on-Change enabled on RB3 and RB5 |

---

## Pin-by-Pin Assignment

### PORTA

| Pin | Direction | Evidence | Function |
|---|---|---|---|
| **RA0** | Output | `MOVWF PORTA ← 0x01`, `CLRF PORTA` | **LED** (toggled high/low as status indicator) |
| **RA1** | Input | `WPUA = 0x02` (bit 1 pull-up) | **Switch** (encoder shaft press or dedicated button, active-low with pull-up) |
| RA2–RA5 | — | No LAT writes or bit tests seen | USB D+/D−, VUSB, or spare |

RA0 is the only PORTA pin actively toggled by the application. The pattern
`MOVWF PORTA ← 0x01` immediately followed later by `CLRF PORTA` at two separate
call sites (PIC addresses `0x171A` and `0x173C`) is consistent with a **status LED**
that lights during USB command acknowledgement or activity.

---

### PORTB (primary input port)

The key input-scanning routine at PIC address `0x1670` reads the entire port:

```asm
MOVF  PORTB,W        ; read all 8 PORTB bits
ANDLW 0x78           ; mask to 0111 1000 → isolate RB3,RB4,RB5,RB6
RRCF  W,F            ; rotate right ×3 (shifts to bits 0,1,2,3)
RRCF  W,F
RRCF  W,F
MOVWF PORTC          ; forward lower nibble to PORTC for routing
BCF   RAM,3          ; clear state flag
BTFSS PORTB,2        ; SEPARATELY test RB2 — branch on its state
```

| Pin | Direction | Evidence | Function |
|---|---|---|---|
| **RB2** | Input | `BTFSS PORTB,2` — bit-tested separately | **Encoder 1 A-phase** or **push-button** |
| **RB3** | Input | `ANDLW 0x78`, `IOCB bit 3` → IOC interrupt | **Encoder 1 B-phase** (IOC triggers on edge) |
| **RB4** | Input | `ANDLW 0x78` | **Encoder 2 A-phase** |
| **RB5** | Input | `ANDLW 0x78`, `IOCB bit 5` → IOC interrupt | **Encoder 2 B-phase** (IOC triggers on edge) |
| **RB6** | Input | `ANDLW 0x78` | **Switch** (button or additional encoder signal) |
| RB0 | Output | `LATB ← 0x01`, toggled/cleared | **LED** (driven high at init, cleared on events) |
| RB1 | — | No explicit access | Spare or shared with USB |
| RB7 | — | No explicit access | PGD (ICSP programming) |

The `IOCB = 0x28` (bits 3 and 5) configures hardware interrupts on **RB3** and **RB5**.
These fire on every edge of those encoder phase signals, feeding the interrupt service
routine at `0x2726`. This is the classic PIC quadrature decoder pattern: one phase
generates the interrupt, the other is polled to determine direction.

---

### PORTC

PORTC is used as both an intermediate data bus and an output driver:

| Pin | Direction | Evidence | Function |
|---|---|---|---|
| **RC0** | Output | `LATC ← 0x01`, toggled/cleared | **LED** (second LED indicator) |
| RC[0:3] | Latched | Written from `(PORTB & 0x78) >> 3` | Temporary signal routing latch |
| RC[upper] | — | `MOVF PORTC,W` reads back | Output comparison / debounce check |

The pattern of writing the shifted PORTB value into PORTC and then immediately reading
PORTC back in two separate branches (one when `PORTB,2 = 1`, another when `= 0`) is a
**quadrature state-machine** approach: PORTC holds the previous encoder state snapshot,
and the two-branch structure produces the four classical Gray-code transitions
(`00→01→11→10→00`) used to count direction.

---

## Functionality

### 1. Quadrature Rotary Encoder Decoding

The firmware reads **two quadrature rotary encoders** using a software state machine.

- **Encoder 1:** A-phase on RB2 (or RB3), B-phase on RB3 (IOC-triggered).
- **Encoder 2:** A-phase on RB4 or RB5, B-phase on RB5 (IOC-triggered).
- The `IOCB` interrupt fires on edge transitions of RB3 and RB5, implementing
  hardware-assisted debounce and direction detection.
- Direction and step count are accumulated in RAM variables and queued for USB
  transmission.

The computed-jump at `0x1682`/`0x1692` (two paths branching on `PORTB,2`, each adding
a different offset `0x86` or `0x84`) implements the standard 4-state quadrature lookup
table — one table for CW, one for CCW.

---

### 2. Push-button Switch Scanning

- **RA1** is an active-low push-button input with internal weak pull-up.
- **RB6** or **RB2** provides a second switch (encoder shaft press).
- Button press events are detected, debounced in software, and reported to the USB host
  as HID button state changes.

---

### 3. LED Status Output

- **RA0** — toggled by the application immediately before and after calling the
  bootloader USB send routine (`CALL 0x3554`). This creates a blink on each USB
  HID packet transmitted, acting as a **TX/activity LED**.
- **RB0 / RC0** — initialised to `0x01` at startup and periodically cleared/set;
  consistent with **power LED** or **link-state LEDs** (e.g. lit when USB enumerated,
  cleared on USB reset).

The pattern:

```asm
MOVLW 0x01
MOVWF PORTA          ; LED on
...
CALL  0x3554         ; send HID packet to host
...
CLRF  PORTA          ; LED off
```

...confirms RA0 is a per-packet activity indicator.

---

### 4. USB HID Device (Encoder Controller)

The bulk of the firmware — all the `UEP`, `UCON`, `UADDR`, `USTAT`, `UFRM` register
accesses — implements a **USB HID device stack** that:

- Enumerates as an HID device to the host PC (VID `0x0C26`, PID `0x001E`).
- Sends encoder increment/decrement and button state packets via USB endpoint 1.
- Receives configuration or command packets from the host on the OUT endpoint.
- Uses the bootloader's resident send/receive service routines at `0x3554` and `0x3898`
  for the low-level USB token handling (so the app does not need its own USB interrupt
  handler).

The `SPBRG` register is written with multiple baud-rate values (`0x01`, `0x02`, `0x04`,
`0x05`, `0x06`, `0x07`, `0x09`) across several functions — these are likely USB timing
parameters or baud-rate negotiation within the HID descriptor response, not a serial
UART implementation.

---

## Summary Pin Table

| Pin | Function | Direction | Notes |
|---|---|---|---|
| **RA0** | Activity LED | Output | Blinks on each USB HID send |
| **RA1** | Push-button | Input | Weak pull-up, active-low |
| **RB0** | Power/Link LED | Output | High at startup, cleared on USB reset |
| **RB2** | Encoder 1 A / SW | Input | Polled in state machine |
| **RB3** | Encoder 1 B | Input | **IOC interrupt** (bit 3 of IOCB) |
| **RB4** | Encoder 2 A | Input | Scanned via `ANDLW 0x78` |
| **RB5** | Encoder 2 B | Input | **IOC interrupt** (bit 5 of IOCB) |
| **RB6** | Switch | Input | Scanned via `ANDLW 0x78` |
| **RC0** | Status LED | Output | High at startup |
| RC[0:3] | Internal latch | Both | Holds shifted PORTB state for quadrature decode |
| D+/D− | USB | — | Handled by hardware USB peripheral |

---

## Architecture Note — Chip Revision

The firmware is **not compatible** with PIC18F14K50 (which has no RB0–RB3).
The most likely replacement candidates consistent with the port map, USB peripheral,
16 KB flash, and 28-pin package are:

| Device | Flash | RAM | PORTB | USB |
|---|---|---|---|---|
| **PIC18F25K50** | 32 KB | 2 KB | RB0–RB7 | Yes |
| **PIC18F2553** | 24 KB | 2 KB | RB0–RB7 | Yes |
| **PIC18F2550** | 32 KB | 2 KB | RB0–RB7 | Yes |

The `0x1400` bootloader boundary (5 KB protected) and 9,488-byte application fit
comfortably within any of these devices.
