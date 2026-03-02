# rc28_decoded_latest.py
# Based on RC28Comm.pde (Processing / Java version) + previous Python insights
# Preference given to the latest provided resource

import hid
import time
import sys

VID = 0x0C26
PID = 0x001E

# Configurable from the code
LONG_PRESS_THRESHOLD_MS = 500
MASK_F1  = 0x02
MASK_F2  = 0x04
MASK_TX  = 0x01
KNOB_CW  = 0x01
KNOB_CCW = 0x02

def main():
    print("=== Icom RC-28 HID Decoder (latest Processing version) ===\n")
    
    try:
        h = hid.device()
        h.open(VID, PID)
        print("Opened:", h.get_product_string())
        print("Manufacturer:", h.get_manufacturer_string() or "N/A")
        print("Serial:", h.get_serial_number_string() or "N/A\n")
    except Exception as e:
        print("Open failed:", e)
        print("Run as Administrator + close RS-BA1/other apps")
        sys.exit(1)

    print("Decoding rules (from RC28Comm.pde):")
    print("  Input report:")
    print(f"    Byte 1 = knob magnitude")
    print(f"    Byte 3 = direction ({KNOB_CW}=CW, {KNOB_CCW}=CCW)")
    print(f"    Byte 5 = buttons (active-low): {MASK_TX:02X}=TX, {MASK_F1:02X}=F1, {MASK_F2:02X}=F2")
    print(f"  Long press threshold: {LONG_PRESS_THRESHOLD_MS} ms\n")
    
    print("Starting monitor... Turn knob / press+hold/release PTT/F1/F2 now")
    print("Ctrl+C to stop\n")

    # Track press times for long/short detection
    f1_down = -1
    f2_down = -1
    tx_down = -1

    # Periodic output report (LED / keep-alive)
    last_poll = time.time()

    try:
        while True:
            # Send keep-alive / LED poll every 150 ms
            if time.time() - last_poll > 0.15:
                # Try LED mask from previous insight (all off, then all on, etc.)
                mask = 0x0F if (int(time.time()) % 4 < 2) else 0x00
                out = [0x00, 0x01, mask] + [0x00] * 61
                try:
                    h.write(out)
                except:
                    pass  # silent fail
                last_poll = time.time()

            # Read input report
            data = h.read(64, timeout_ms=120)
            if data and len(data) >= 6:
                # From RC28Comm.pde decode logic
                dir_flag = data[3] & 0xFF
                btn_byte = data[5] & 0xFF

                ts = time.strftime("%H:%M:%S")

                # Wheel / encoder movement
                if dir_flag == KNOB_CW:
                    steps = data[1]
                    print(f"[{ts}] KNOB CW  +{steps} steps")
                elif dir_flag == KNOB_CCW:
                    steps = data[1]
                    print(f"[{ts}] KNOB CCW -{steps} steps")

                # Buttons (active-low: 0 = pressed)
                f1_now  = (btn_byte & MASK_F1) == 0
                f2_now  = (btn_byte & MASK_F2) == 0
                tx_now  = (btn_byte & MASK_TX) == 0

                now_ms = time.time() * 1000

                # F1
                if f1_now and f1_down < 0:
                    f1_down = now_ms
                elif not f1_now and f1_down >= 0:
                    duration = now_ms - f1_down
                    is_long = duration >= LONG_PRESS_THRESHOLD_MS
                    print(f"[{ts}] F1 {'LONG' if is_long else 'SHORT'} press ({duration:.0f} ms)")
                    f1_down = -1

                # F2
                if f2_now and f2_down < 0:
                    f2_down = now_ms
                elif not f2_now and f2_down >= 0:
                    duration = now_ms - f2_down
                    is_long = duration >= LONG_PRESS_THRESHOLD_MS
                    print(f"[{ts}] F2 {'LONG' if is_long else 'SHORT'} press ({duration:.0f} ms)")
                    f2_down = -1

                # Transmit / PTT
                if tx_now and tx_down < 0:
                    tx_down = now_ms
                elif not tx_now and tx_down >= 0:
                    duration = now_ms - tx_down
                    print(f"[{ts}] TX / PTT press ({duration:.0f} ms)")
                    tx_down = -1

                # Raw hex for debug/verification
                raw = " ".join(f"{b:02X}" for b in data[:12])
                print(f"  RAW first 12: {raw}")

            time.sleep(0.02)  # fast non-blocking loop

    except KeyboardInterrupt:
        print("\nStopped by user.")
    except Exception as e:
        print("Error:", e)
    finally:
        h.close()
        print("Device closed.")

if __name__ == "__main__":
    main()