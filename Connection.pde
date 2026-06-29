// ============================================================
// Connection.pde
// Data-source selection + transport management for TDF_Visual.
//
// Two sources share one parser (SensorReceiver.parseCSVLine):
//   CONN_SERIAL — processing.serial (initReceiver / serialEvent)
//   CONN_BLE    — launches ble_bridge.py and reads its stdout (x,y,z lines)
//
// On startup connMode = CONN_NONE and draw() shows the chooser (two buttons).
// Picking a source starts that transport and a fresh baseline calibration.
// ============================================================

static final int CONN_NONE   = 0;
static final int CONN_SERIAL = 1;
static final int CONN_BLE    = 2;

int connMode = CONN_NONE;

// --- BLE bridge process state ---
Process _bleProc = null;
boolean _bleStarted = false;          // BLE source chosen + launch attempted
boolean _bleProcAlive = false;        // main-thread-only liveness flag
String _bleStatus = "Idle";
boolean _bleHookAdded = false;

// ============================================================
// Source selection
// ============================================================
void startSerial() {
  resetReceiverState();
  connMode = CONN_SERIAL;
  initReceiver();    // SensorReceiver.pde — opens the serial port
  initBaseline();    // restart calibration for this session
  println("[Connection] Source = SERIAL");
}

void startBLE() {
  resetReceiverState();
  connMode = CONN_BLE;
  _bleStatus = "Starting BLE bridge ...";
  launchBleBridge();
  initBaseline();    // restart calibration for this session
  println("[Connection] Source = BLE");
}

// Zero the shared receiver globals so each new session starts clean (frame
// counts, LIVE/HOLD + BAD badges, and the BLE "waiting for first frame" gate).
void resetReceiverState() {
  sensorBx = 0;
  sensorBy = 0;
  sensorBz = 0;
  newDataAvailable = false;
  _validFrameCount = 0;
  _badFrameCount = 0;
  _lastBadLine = "";
}

// Unified readiness gate used by draw()/mouse/keys.
boolean isConnectionReady() {
  if (connMode == CONN_SERIAL) return isReceiverReady();
  if (connMode == CONN_BLE)    return true;   // the BLE screen reports waiting/errors
  return false;
}

// Per-frame transport housekeeping (replaces updateReceiver in draw()).
void updateConnection() {
  if (connMode == CONN_BLE && _bleStarted && _bleProc != null
      && _bleProcAlive && !_bleProc.isAlive()) {
    _bleProcAlive = false;
    _bleStatus = "Bridge stopped. Check Python / 'pip install bleak'.";
  }
}

// Tear down the current source and return to the chooser.
void resetToChooser() {
  if (connMode == CONN_BLE) {
    stopBleBridge();
  } else if (connMode == CONN_SERIAL) {
    try { if (_port != null) _port.stop(); } catch (Exception e) { }
    _port = null;
    _receiverReady = false;
  }
  connMode = CONN_NONE;
  println("[Connection] Returned to source chooser.");
}

// ============================================================
// BLE bridge process (ble_bridge.py) — mirrors runDataConversion()'s launcher
// ============================================================
void launchBleBridge() {
  String script = sketchPath("ble_bridge.py");
  if (!new File(script).exists()) {
    _bleStatus = "ble_bridge.py not found in sketch folder.";
    println("[Connection] " + _bleStatus);
    return;
  }

  String[] pythonCandidates = {
    "python",
    "python3",
    "C:\\Program Files\\Python312\\python.exe",
    "C:\\Program Files\\Python311\\python.exe",
    "C:\\Program Files\\Python310\\python.exe"
  };

  for (String py : pythonCandidates) {
    try {
      // -u keeps the child's stdout unbuffered so frames arrive with low latency.
      ProcessBuilder pb = new ProcessBuilder(py, "-u", script);
      pb.directory(new File(sketchPath("")));
      // Keep stdout (data) and stderr (status) separate — do NOT merge them.
      _bleProc = pb.start();
      _bleStarted = true;
      _bleProcAlive = true;
      _bleStatus = "Scanning for TDF_Sensor ...";
      startBleReaderThreads();
      addBleShutdownHook();
      println("[Connection] BLE bridge launched with " + py);
      return;
    } catch (Exception e) {
      // try next candidate
    }
  }

  _bleStarted = true;   // mark as attempted so the BLE screen (not serial) shows
  _bleStatus = "Python not found. Install Python 3 + 'pip install bleak'.";
  println("[Connection] " + _bleStatus);
}

// Two daemon threads: stdout -> parser, stderr -> status (same threading model
// Processing already uses for serialEvent, so writing the sensor globals here
// is consistent).
void startBleReaderThreads() {
  final Process proc = _bleProc;

  Thread out = new Thread(new Runnable() {
    public void run() {
      try {
        java.io.BufferedReader br = new java.io.BufferedReader(
          new java.io.InputStreamReader(proc.getInputStream()));
        String ln;
        while ((ln = br.readLine()) != null) {
          parseCSVLine(trim(ln));   // SensorReceiver.pde
        }
      } catch (Exception e) {
        // pipe closed on shutdown — ignore
      }
    }
  });
  out.setDaemon(true);
  out.start();

  Thread err = new Thread(new Runnable() {
    public void run() {
      try {
        java.io.BufferedReader br = new java.io.BufferedReader(
          new java.io.InputStreamReader(proc.getErrorStream()));
        String ln;
        while ((ln = br.readLine()) != null) {
          _bleStatus = ln;
          println("[ble_bridge] " + ln);
        }
      } catch (Exception e) {
        // pipe closed on shutdown — ignore
      }
    }
  });
  err.setDaemon(true);
  err.start();
}

void stopBleBridge() {
  try {
    if (_bleProc != null) _bleProc.destroy();
  } catch (Exception e) { }
  _bleProc = null;
  _bleStarted = false;
  _bleProcAlive = false;
}

// Make sure the child process dies with the sketch, however it exits.
void addBleShutdownHook() {
  if (_bleHookAdded) return;
  _bleHookAdded = true;
  Runtime.getRuntime().addShutdownHook(new Thread(new Runnable() {
    public void run() { stopBleBridge(); }
  }));
}

// ============================================================
// Connection chooser screen (two buttons: Serial / BLE)
// ============================================================
static final int CH_PANEL_W = 620;
static final int CH_PANEL_H = 320;
static final int CH_PX = (DESIGN_W - CH_PANEL_W) / 2;
static final int CH_PY = (DESIGN_H - CH_PANEL_H) / 2;

static final int CH_CARD_W = 260;
static final int CH_CARD_H = 160;
static final int CH_CARD_Y = CH_PY + 110;
static final int CH_CARD1_X = CH_PX + 35;
static final int CH_CARD2_X = CH_PX + 35 + CH_CARD_W + 30;

boolean isSerialCardHit(float mx, float my) {
  return mx >= CH_CARD1_X && mx <= CH_CARD1_X + CH_CARD_W &&
         my >= CH_CARD_Y && my <= CH_CARD_Y + CH_CARD_H;
}

boolean isBleCardHit(float mx, float my) {
  return mx >= CH_CARD2_X && mx <= CH_CARD2_X + CH_CARD_W &&
         my >= CH_CARD_Y && my <= CH_CARD_Y + CH_CARD_H;
}

void handleChooserClick(float mx, float my) {
  if (isSerialCardHit(mx, my)) startSerial();
  else if (isBleCardHit(mx, my)) startBLE();
}

void drawConnectionChooser() {
  drawPanelBase(CH_PX, CH_PY, CH_PANEL_W, CH_PANEL_H, "Startup");

  fill(UI_TEXT);
  useUIFont(22);
  textAlign(CENTER, TOP);
  text("Select Data Source", CH_PX + CH_PANEL_W / 2.0, CH_PY + 36);

  fill(UI_MUTED);
  useUIFont(12);
  text("Choose how this sketch receives sensor frames",
       CH_PX + CH_PANEL_W / 2.0, CH_PY + 70);

  float mx = uiMouseX();
  float my = uiMouseY();
  drawSourceCard(CH_CARD1_X, CH_CARD_Y, "Serial (USB)",
                 "Wired MLX90393 over COM port", UI_X, isSerialCardHit(mx, my));
  drawSourceCard(CH_CARD2_X, CH_CARD_Y, "Bluetooth LE",
                 "Wireless ESP32 'TDF_Sensor'", UI_GOOD, isBleCardHit(mx, my));

  fill(UI_MUTED);
  useUIFont(11);
  textAlign(CENTER, TOP);
  text("shortcuts:  [S] Serial    [B] Bluetooth",
       CH_PX + CH_PANEL_W / 2.0, CH_PY + CH_PANEL_H - 30);

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

void drawSourceCard(int x, int y, String title, String sub, color accent, boolean hover) {
  noStroke();
  fill(hover ? UI_PANEL_HI : UI_PANEL_2);
  rect(x, y, CH_CARD_W, CH_CARD_H, 10);
  stroke(hover ? UI_BORDER_ACTIVE : UI_BORDER);
  strokeWeight(hover ? 2 : 1);
  noFill();
  rect(x + 0.5, y + 0.5, CH_CARD_W - 1, CH_CARD_H - 1, 10);
  noStroke();

  // accent chip
  fill(accent);
  rect(x + 20, y + 24, 46, 6, 3);

  fill(UI_TEXT);
  useUIFont(20);
  textAlign(LEFT, TOP);
  text(title, x + 20, y + 48);

  fill(UI_MUTED);
  useUIFont(12);
  text(sub, x + 20, y + 86);

  fill(hover ? accent : UI_MUTED);
  useUIFont(12);
  text(hover ? "click to connect >" : "click to select", x + 20, y + CH_CARD_H - 30);
}

// ============================================================
// BLE "connecting / waiting for data" screen
// ============================================================
void drawBleConnecting() {
  int cx = DESIGN_W / 2;
  int cy = DESIGN_H / 2 - 20;
  textAlign(CENTER, CENTER);

  // spinner
  noFill();
  strokeWeight(3);
  for (int i = 0; i < 12; i++) {
    float a = frameCount * 0.12 - i * 0.5;
    float alpha = map(i, 0, 11, 30, 220);
    stroke(red(UI_GOOD), green(UI_GOOD), blue(UI_GOOD), alpha);
    float r1 = 26, r2 = 38;
    float ca = cos(a), sa = sin(a);
    line(cx + ca * r1, cy + sa * r1, cx + ca * r2, cy + sa * r2);
  }
  noStroke();

  fill(UI_TEXT);
  textSize(30);
  text("Bluetooth LE", cx, cy + 90);

  fill(UI_GOOD);
  useUIFont(14);
  text(_bleStatus, cx, cy + 128);

  fill(UI_MUTED);
  useUIFont(12);
  text("Power on the ESP32 'TDF_Sensor' and keep it advertising.", cx, cy + 158);

  textAlign(LEFT, BASELINE);
  textSize(14);
  noStroke();
}

// ============================================================
// Back button (shown on the waiting / no-connection screens)
// ============================================================
static final int BK_X = 24;
static final int BK_Y = 24;
static final int BK_W = 120;
static final int BK_H = 34;

boolean isBackButtonHit(float mx, float my) {
  return mx >= BK_X && mx <= BK_X + BK_W && my >= BK_Y && my <= BK_Y + BK_H;
}

void drawBackButton(boolean hover) {
  noStroke();
  fill(hover ? UI_BORDER_ACTIVE : UI_PANEL_HI);
  rect(BK_X, BK_Y, BK_W, BK_H, 6);
  fill(UI_TEXT);
  useUIFont(13);
  textAlign(CENTER, CENTER);
  text("< Back", BK_X + BK_W / 2.0, BK_Y + BK_H / 2.0 + 1);
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}
