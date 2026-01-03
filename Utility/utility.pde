// =====================================================
// RC-28 HID Probe Console (Processing + hid4java + reflection)
// =====================================================

import org.hid4java.*;
import java.lang.reflect.*;

// RC-28 IDs
final int RC28_VENDOR_ID  = 0x0C26;
final int RC28_PRODUCT_ID = 0x001E;

// Globals
HidServices hid;
HidDevice rc28;
boolean rc28Opened = false;

String status = "Starting...";
String lastIn = "";

// LED probe state
int currentReportId = 0x01;  // start with 1 (known to do something)
int currentByteIndex = 0;    // which payload byte we are editing (0-7)
int currentValue = 0x01;     // value to send in that byte (0-255)

ReflectionWriter writer = new ReflectionWriter();

void setup() {
  size(900, 500);
  println("=== RC-28 HID Probe Console ===");

  initHID();
  findRC28();

  if (rc28 != null) {
    println("[HID] Attempting rc28.open() via reflection...");

    boolean ok = false;

    try {
      Method m = rc28.getClass().getMethod("open");
      Object result = m.invoke(rc28);

      if (result instanceof Boolean) {
        ok = ((Boolean)result).booleanValue();
      } else {
        ok = true;
      }

    } catch (Exception e) {
      println("[ERROR] Exception calling rc28.open() via reflection");
      e.printStackTrace();
    }

    println("[HID] rc28.open() (reflection) returned: " + ok);
    rc28Opened = ok;

    if (ok) {
      status = "RC-28 opened";
    } else {
      status = "RC-28 found but open() failed";
    }

  } else {
    status = "RC-28 not found";
  }
}

void draw() {
  background(20);
  fill(255);
  textSize(14);

  text("RC-28 HID Probe Console", 10, 20);
  text("Status: " + status, 10, 40);

  text("Last input report:", 10, 80);
  text(lastIn, 10, 100);

  int y = 140;
  text("Known commands:", 10, y);          y += 20;
  text("  [1] Mode 1  -> L+F1+F2 ON, TX OFF", 10, y); y += 20;
  text("  [2] Mode 2  -> ALL LEDs ON",       10, y); y += 30;

  text("Probe controls:", 10, y);          y += 20;
  text("  [r/R] reportId ++/--", 10, y);   y += 20;
  text("  [i/I] byteIndex ++/-- (0-7)", 10, y); y += 20;
  text("  [v/V] value ++/-- (1 steps)", 10, y); y += 20;
  text("  [f/F] value ++/-- (16 steps)", 10, y); y += 20;
  text("  [s]    send probe packet", 10, y); y += 30;

  text("Current probe state:", 10, y);     y += 20;
  text("  reportId     = 0x" + hex(currentReportId, 2) + " (" + currentReportId + ")", 10, y); y += 20;
  text("  byteIndex    = " + currentByteIndex, 10, y); y += 20;
  text("  value        = 0x" + hex(currentValue, 2) + " (" + currentValue + ")", 10, y); y += 20;

  pollInput();
}

void keyPressed() {
  if (!rc28Opened) {
    println("[KEY] RC-28 not opened");
    return;
  }

  // ------------------------------
  // Known high-level LED commands
  // ------------------------------
  if (key == '1') {
    byte reportId = 0x01;
    byte[] payload = new byte[8];
    payload[0] = 0x01;
    println("[KEY] Mode 1: payload[0] = 0x01  (L+F1+F2 ON, TX OFF)");
    writer.sendReport(rc28, reportId, payload);
    return;
  }

  if (key == '2') {
    byte reportId = 0x01;
    byte[] payload = new byte[8];
    payload[0] = 0x02;
    println("[KEY] Mode 2: payload[0] = 0x02  (ALL LEDs ON)");
    writer.sendReport(rc28, reportId, payload);
    return;
  }

  // ------------------------------
  // Probe parameter adjustments
  // ------------------------------
  if (key == 'r') {
    currentReportId++;
    if (currentReportId > 0x0F) {
      currentReportId = 0x0F;
    }
    println("[PROBE] reportId -> 0x" + hex(currentReportId, 2));
    return;
  }

  if (key == 'R') {
    currentReportId--;
    if (currentReportId < 0x01) {
      currentReportId = 0x01;
    }
    println("[PROBE] reportId -> 0x" + hex(currentReportId, 2));
    return;
  }

  if (key == 'i') {
    currentByteIndex++;
    if (currentByteIndex > 7) {
      currentByteIndex = 7;
    }
    println("[PROBE] byteIndex -> " + currentByteIndex);
    return;
  }

  if (key == 'I') {
    currentByteIndex--;
    if (currentByteIndex < 0) {
      currentByteIndex = 0;
    }
    println("[PROBE] byteIndex -> " + currentByteIndex);
    return;
  }

  if (key == 'v') {
    currentValue++;
    if (currentValue > 255) {
      currentValue = 255;
    }
    println("[PROBE] value -> 0x" + hex(currentValue, 2) + " (" + currentValue + ")");
    return;
  }

  if (key == 'V') {
    currentValue--;
    if (currentValue < 0) {
      currentValue = 0;
    }
    println("[PROBE] value -> 0x" + hex(currentValue, 2) + " (" + currentValue + ")");
    return;
  }

  if (key == 'f') {
    currentValue += 16;
    if (currentValue > 255) {
      currentValue = 255;
    }
    println("[PROBE] value -> 0x" + hex(currentValue, 2) + " (" + currentValue + ")");
    return;
  }

  if (key == 'F') {
    currentValue -= 16;
    if (currentValue < 0) {
      currentValue = 0;
    }
    println("[PROBE] value -> 0x" + hex(currentValue, 2) + " (" + currentValue + ")");
    return;
  }

  // ------------------------------
  // Send probe packet
  // ------------------------------
  if (key == 's') {
    byte reportId = (byte)currentReportId;
    byte[] payload = new byte[8];
    // Only set one byte – keep it sparse so effects are attributable
    payload[currentByteIndex] = (byte)(currentValue & 0xFF);

    println("[PROBE SEND] reportId=0x" + hex(currentReportId, 2) +
            " byte[" + currentByteIndex + "]=0x" + hex(currentValue, 2) +
            " (" + currentValue + ")");

    writer.sendReport(rc28, reportId, payload);
    return;
  }
}


// =====================================================
// HID init + enumeration
// =====================================================

void initHID() {
  try {
    HidServicesSpecification spec = new HidServicesSpecification();
    spec.setAutoShutdown(true);
    hid = HidManager.getHidServices(spec);
    println("[HID] HidServices initialized");
  } catch (Exception e) {
    println("[ERROR] HidServices init failed");
    e.printStackTrace();
  }
}

void findRC28() {
  if (hid == null) return;

  println("== HID Devices ==");
  for (HidDevice d : hid.getAttachedHidDevices()) {
    println("VID=0x" + hex(d.getVendorId(), 4) +
            " PID=0x" + hex(d.getProductId(), 4) +
            " | " + d.getManufacturer() +
            " | " + d.getProduct());
  }

  rc28 = hid.getHidDevice(RC28_VENDOR_ID, RC28_PRODUCT_ID, null);

  if (rc28 != null) {
    println("[HID] RC-28 FOUND: " + rc28.getManufacturer() + " - " + rc28.getProduct());
  } else {
    println("[HID] RC-28 not found");
  }
}


// =====================================================
// Poll input reports (no threads, PDE-safe)
// =====================================================

void pollInput() {
  if (!rc28Opened) return;

  byte[] buf = new byte[64];
  int n = 0;

  try {
    n = rc28.read(buf, 1);  // 1ms poll
  } catch (Exception e) {
    return;
  }

  if (n > 0) {
    String s = "";
    for (int i = 0; i < n; i++) {
      s += nf(buf[i] & 0xFF, 2) + " ";
    }
    lastIn = s;
    println("[IN] " + s);
  }
}


// =====================================================
// Reflection-based HID writer (safe version)
// =====================================================

class ReflectionWriter {

  boolean sendReport(Object dev, byte reportId, byte[] payload) {
    if (dev == null) return false;

    byte[] data = new byte[payload.length + 1];
    data[0] = reportId;
    arrayCopy(payload, 0, data, 1, payload.length);

    if (tryWrite3(dev, data, reportId)) return true;
    if (tryWrite2(dev, data)) return true;
    if (tryWrite1(dev, data)) return true;

    println("[Writer] No usable write() method found");
    return false;
  }

  boolean tryWrite3(Object dev, byte[] data, byte reportId) {
    try {
      Method m = dev.getClass().getMethod("write", byte[].class, int.class, byte.class);
      m.invoke(dev, data, data.length, reportId);
      log("write3", data);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  boolean tryWrite2(Object dev, byte[] data) {
    try {
      Method m = dev.getClass().getMethod("write", byte[].class, int.class);
      m.invoke(dev, data, data.length);
      log("write2", data);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  boolean tryWrite1(Object dev, byte[] data) {
    try {
      Method m = dev.getClass().getMethod("write", byte[].class);
      m.invoke(dev, (Object)data);
      log("write1", data);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  void log(String tag, byte[] data) {
    String s = "";
    for (int i = 0; i < data.length; i++) {
      s += nf(data[i] & 0xFF, 2) + " ";
    }
    println("[OUT " + tag + "] " + s);
  }
}
