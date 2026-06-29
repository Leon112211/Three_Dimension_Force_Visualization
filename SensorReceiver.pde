// ============================================================
// SensorReceiver.pde
// Serial receiver for numeric magnetic-field frames.
//
// Accepted data frames:
//   Bx,By,Bz
//   SensorID,Bx,By,Bz
//   Bx,By,Bz,Fx,Fy,Fz
//
// Semicolon-separated legacy frames are accepted too.
// Debug/header/invalid frames are skipped and never update sensorBx/By/Bz.
// ============================================================

import processing.serial.*;

static final int BAUD_RATE = 115200;
static final String PORT_HINT = "COM";

float sensorBx = 0;
float sensorBy = 0;
float sensorBz = 0;
boolean newDataAvailable = false;
int _lastSampleMs = 0;                    // millis() of the last valid frame
static final int LIVE_TIMEOUT_MS = 400;  // LIVE if a frame arrived within this window

Serial _port;
boolean _receiverReady = false;
int _validFrameCount = 0;
int _badFrameCount = 0;
String _lastBadLine = "";

void initReceiver() {
  String[] ports = Serial.list();

  if (ports.length == 0) {
    println("[SensorReceiver] No serial ports detected. Data reception disabled.");
    return;
  }

  println("[SensorReceiver] Available serial ports:");
  for (int i = 0; i < ports.length; i++) {
    println("  [" + i + "] " + ports[i]);
  }

  String selectedPort = ports[ports.length - 1];
  for (String p : ports) {
    if (p.indexOf(PORT_HINT) >= 0) {
      selectedPort = p;
      break;
    }
  }

  try {
    _port = new Serial(this, selectedPort, BAUD_RATE);
    _port.bufferUntil('\n');
    _receiverReady = true;
    println("[SensorReceiver] Connected: " + selectedPort + "  baud: " + BAUD_RATE);
  } catch (Exception e) {
    println("[SensorReceiver] Connection failed: " + e.getMessage());
  }
}

void updateReceiver() {
  // Serial frames are handled by serialEvent().
}

void serialEvent(Serial port) {
  if (port != _port) return;

  String line = port.readStringUntil('\n');
  if (line == null) return;

  line = trim(line);
  if (line.length() == 0) return;

  parseCSVLine(line);
}

void parseCSVLine(String line) {
  if (shouldIgnoreSerialLine(line)) return;

  String normalized = line.replace(';', ',');
  String[] parts = split(normalized, ',');
  int startCol = -1;

  if (parts.length == 3) {
    startCol = 0;
  } else if (parts.length == 4) {
    startCol = 1;
  } else if (parts.length >= 6) {
    startCol = 0;
  } else {
    recordBadFrame(line, "unrecognized column count: " + parts.length);
    return;
  }

  try {
    float bx = float(trim(parts[startCol]));
    float by = float(trim(parts[startCol + 1]));
    float bz = float(trim(parts[startCol + 2]));

    if (!areFiniteValues(bx, by, bz)) {
      recordBadFrame(line, "non-finite numeric value");
      return;
    }

    sensorBx = bx;
    sensorBy = by;
    sensorBz = bz;
    newDataAvailable = true;
    _lastSampleMs = millis();
    _validFrameCount++;
  } catch (Exception e) {
    recordBadFrame(line, "parse error: " + e.getMessage());
  }
}

boolean shouldIgnoreSerialLine(String line) {
  if (line.length() == 0) return true;
  if (line.charAt(0) == '#') return true;
  if (line.indexOf(':') >= 0 || line.indexOf('=') >= 0) {
    recordBadFrame(line, "debug/header line");
    return true;
  }
  return false;
}

boolean areFiniteValues(float x, float y, float z) {
  return isFiniteValue(x) && isFiniteValue(y) && isFiniteValue(z);
}

boolean isFiniteValue(float v) {
  return !Float.isNaN(v) && !Float.isInfinite(v);
}

boolean isCurrentSensorFrameFinite() {
  return areFiniteValues(sensorBx, sensorBy, sensorBz);
}

void recordBadFrame(String line, String reason) {
  _badFrameCount++;
  _lastBadLine = line;
  if (_badFrameCount <= 5 || _badFrameCount % 50 == 0) {
    println("[SensorReceiver] Skipped invalid frame #" + _badFrameCount
            + " (" + reason + "): " + shortenSerialLine(line));
  }
}

String shortenSerialLine(String line) {
  if (line.length() <= 120) return line;
  return line.substring(0, 117) + "...";
}

boolean isReceiverReady() {
  return _receiverReady;
}

// Stream is "live" if a valid frame arrived recently. Time-based, so the badge
// stays steady while data flows (~50 Hz) instead of flickering every draw frame;
// it only goes HOLD when data genuinely stops (disconnect / power-off / stall).
boolean isStreamLive() {
  return _validFrameCount > 0 && (millis() - _lastSampleMs) < LIVE_TIMEOUT_MS;
}

int receiverValidFrameCount() {
  return _validFrameCount;
}

int receiverBadFrameCount() {
  return _badFrameCount;
}

String receiverLastBadLine() {
  return _lastBadLine;
}
