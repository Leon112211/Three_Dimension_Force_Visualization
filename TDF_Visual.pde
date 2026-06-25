// ============================================================
// TDF_Visual.pde — Main entry
// Three-Dimensional Force Sensor Visualization
// Sensor models: H2 / H4 / H6
//
// Flow: Serial CSV → Baseline calibration → Decoupling F=D*dV → HUD
// Keyboard shortcuts:
//   [T]   Toggle S / D view
//   [1/2/3] Select sensor H2 / H4 / H6
// ============================================================

static final int DESIGN_W = 1350;
static final int DESIGN_H = 940;
static final float STARTUP_UI_SCALE = 0.78;
static final float START_SCREEN_W = 0.82;
static final float START_SCREEN_H = 0.82;
static final float MIN_STARTUP_SCALE = 0.45;
static final float MAX_UI_SCALE = 1.25;

float _uiScale = 1.0;
float _uiOffsetX = 0;
float _uiOffsetY = 0;

float _lastDVx = 0;
float _lastDVy = 0;
float _lastDVz = 0;
boolean _warnedInvalidComputation = false;

void settings() {
  float scaleW = (displayWidth * START_SCREEN_W) / (float) DESIGN_W;
  float scaleH = (displayHeight * START_SCREEN_H) / (float) DESIGN_H;
  float fitScale = min(scaleW, scaleH);
  float startupScale = min(STARTUP_UI_SCALE, fitScale);
  if (fitScale >= MIN_STARTUP_SCALE) {
    startupScale = max(startupScale, MIN_STARTUP_SCALE);
  }
  startupScale = min(startupScale, MAX_UI_SCALE);
  size(round(DESIGN_W * startupScale), round(DESIGN_H * startupScale), P2D);
  pixelDensity(displayDensity());   // render at the display's native density (HiDPI / retina / 4K)
  smooth(2);                        // light antialiasing (2x MSAA; 4x looked nicer but is heavy on iGPUs)
}

void setup() {
  surface.setResizable(true);
  centerWindowOnScreen();
  initTheme();
  useUIFont(14);
  textAlign(LEFT, BASELINE);

  initReceiver();     // SensorReceiver.pde
  initDecoupling();   // Decoupling.pde — build S and D matrices
  initForceView();    // ForceView.pde  — 3D arrows + bar chart
  initPressureGrid(); // PressureGrid.pde — Z-axis pressure surface
  initCompass();      // TangentialCompass.pde — XY force compass
  initPlot();         // SensorPlot.pde  — real-time Bx/By/Bz waveform
  initRangePanel();   // RangePanel.pde  — global X/Y/Z display ranges
  initBaseline();     // Baseline.pde   — begin 300-sample calibration
}

void draw() {
  background(UI_BG);
  updateUILayout();
  pushMatrix();
  translate(_uiOffsetX, _uiOffsetY);
  scale(_uiScale);
  drawAppBackdrop();

  updateReceiver();

  // --- serial not connected ---
  if (!isReceiverReady()) {
    drawNoConnection();
    popMatrix();
    return;
  }

  // --- always push sensor data into waveform buffer ---
  if (newDataAvailable) {
    updatePlot();
  }

  // --- baseline calibration phase ---
  if (newDataAvailable && !isBaselineDone()) {
    updateBaseline();
  }
  if (!isBaselineDone()) {
    drawBaselineHUD();
    newDataAvailable = false;
    popMatrix();
    return;
  }

  // --- compute decoupled force ---
  boolean canComputeForce = isCurrentSensorFrameFinite()
                         && areFiniteValues(baselineX, baselineY, baselineZ);
  if (canComputeForce) {
    _lastDVx = sensorBx - baselineX;
    _lastDVy = sensorBy - baselineY;
    _lastDVz = sensorBz - baselineZ;
    computeForce(_lastDVx, _lastDVy, _lastDVz);
    _warnedInvalidComputation = false;
  } else if (!_warnedInvalidComputation) {
    println("[TDF] Invalid serial frame skipped; keeping last valid force display.");
    _warnedInvalidComputation = true;
  }

  float dVx = _lastDVx;
  float dVy = _lastDVy;
  float dVz = _lastDVz;

  drawTopHUD(dVx, dVy, dVz);

  newDataAvailable = false;

  // --- 3D force view + bar chart ---
  drawForceView();

  // --- Z-axis pressure surface ---
  drawPressureGrid();

  // --- XY tangential force compass ---
  drawCompass(forceX, forceY);

  // --- real-time sensor waveform ---
  drawPlot();

  // --- global X/Y/Z display ranges ---
  drawRangePanel();

  // --- always-visible matrix overlay (on top of everything) ---
  drawMatrixHUD();

  popMatrix();
}

void drawTopHUD(float dVx, float dVy, float dVz) {
  int x = 30;
  int y = 30;
  int w = 820;
  int h = 160;
  drawPanelBase(x, y, w, h, "Sensor State");

  useUIFont(18);
  textAlign(LEFT, TOP);
  fill(UI_TEXT);
  text("TDF Visual", x + 16, y + 30);

  // Badges flow left-to-right after the title (adapts to the title's actual width).
  float by = y + 29;
  float bx = x + 16 + textWidth("TDF Visual") + 16;
  bx = drawBadgeFlow(bx, by, SENSOR_NAMES[activeSensor], UI_PANEL_HI, UI_TEXT) + 8;
  bx = drawBadgeFlow(bx, by, newDataAvailable ? "LIVE" : "HOLD",
                     newDataAvailable ? color(36, 92, 62) : color(64, 68, 78),
                     newDataAvailable ? UI_GOOD : UI_MUTED) + 8;
  if (receiverBadFrameCount() > 0) {
    drawBadgeFlow(bx, by, "BAD " + receiverBadFrameCount(), color(78, 51, 28), UI_WARN);
  }

  // Calibration button (top-right) — click to recalibrate baseline
  drawCalibrationButton(isCalibrationButtonHit(uiMouseX(), uiMouseY()));

  // FPS readout (left of the Calibration button)
  drawFpsReadout();

  int baseX0 = x + 18;       // Baseline (first column)
  int magX = x + 240;        // Magnetic delta
  int forceX0 = x + 462;     // Decoupled force
  int baseY = y + 82;        // below the title/badge/button row -> no overlap
  int rowH = 22;

  useUIFont(11);
  textAlign(LEFT, TOP);
  fill(UI_MUTED);
  text("Baseline (uT)", baseX0, baseY - 22);
  text("Magnetic delta (uT)", magX, baseY - 22);
  text("Decoupled force (N)", forceX0, baseY - 22);

  drawReadoutRow(baseX0, baseY, "Bx", baselineX, UI_X);
  drawReadoutRow(baseX0, baseY + rowH, "By", baselineY, UI_Y);
  drawReadoutRow(baseX0, baseY + rowH * 2, "Bz", baselineZ, UI_Z);

  drawReadoutRow(magX, baseY, "dBx", dVx, UI_X);
  drawReadoutRow(magX, baseY + rowH, "dBy", dVy, UI_Y);
  drawReadoutRow(magX, baseY + rowH * 2, "dBz", dVz, UI_Z);

  drawReadoutRow(forceX0, baseY, "Fx", forceX, UI_X);
  drawReadoutRow(forceX0, baseY + rowH, "Fy", forceY, UI_Y);
  drawReadoutRow(forceX0, baseY + rowH * 2, "Fz", forceZ, UI_Z);

  useUIFont(14);
}

void drawReadoutRow(int x, int y, String label, float value, color c) {
  useMonoFont(14);
  textAlign(LEFT, TOP);
  fill(c);
  text(label, x, y);
  fill(UI_TEXT);
  text(nf(value, 1, 4), x + 44, y);
}

// --- Calibration button (clickable, in the Top HUD) ---
static final int CAL_BTN_X = 726;
static final int CAL_BTN_Y = 55;
static final int CAL_BTN_W = 110;
static final int CAL_BTN_H = 30;

boolean isCalibrationButtonHit(float mx, float my) {
  return mx >= CAL_BTN_X && mx <= CAL_BTN_X + CAL_BTN_W &&
         my >= CAL_BTN_Y && my <= CAL_BTN_Y + CAL_BTN_H;
}

void drawCalibrationButton(boolean hover) {
  noStroke();
  fill(hover ? UI_BORDER_ACTIVE : UI_PANEL_HI);
  rect(CAL_BTN_X, CAL_BTN_Y, CAL_BTN_W, CAL_BTN_H, 6);
  fill(UI_TEXT);
  useUIFont(13);
  textAlign(CENTER, CENTER);
  text("Calibration", CAL_BTN_X + CAL_BTN_W / 2.0, CAL_BTN_Y + CAL_BTN_H / 2.0 + 1);
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

// --- FPS readout (top-right of the Sensor State panel, left of Calibration) ---
void drawFpsReadout() {
  float fps = frameRate;   // Processing's built-in smoothed frame rate
  color c = fps >= 50 ? UI_GOOD : (fps >= 30 ? UI_WARN : UI_DANGER);
  int fw = 96;
  int fh = CAL_BTN_H;
  int fx = CAL_BTN_X - fw - 14;
  int fy = CAL_BTN_Y;
  noStroke();
  fill(UI_PANEL_HI);
  rect(fx, fy, fw, fh, 6);
  fill(UI_MUTED);
  useUIFont(10);
  textAlign(LEFT, CENTER);
  text("FPS", fx + 10, fy + fh / 2.0 + 1);
  fill(c);
  useMonoFont(15);
  textAlign(RIGHT, CENTER);
  text(nf(fps, 1, 1), fx + fw - 10, fy + fh / 2.0 + 1);
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

// ============================================================
// Input handlers
// ============================================================
void keyPressed() {
  // [C] — recalibrate baseline
  if (key == 'c' || key == 'C') {
    if (isReceiverReady()) {
      initBaseline();
      println("[TDF] Baseline recalibration triggered by user.");
    }
    return;
  }

  handleMatrixKey(key);
}

void mouseDragged() {
  updateUILayout();
  if (_rangeDragging >= 0) { updateRangeSlider(_rangeDragging); return; }   // axis range sliders
  if (_spSliderDragging) { updatePlotSlider(); return; }                    // waveform points slider
  if (!_pgDragging) handleFVDrag();   // skip ForceView while orbiting the pressure grid
  handlePGDrag();
}

void mouseReleased() {
  endPGDrag();
  endRangeDrag();
  endPlotSliderDrag();
}

void mousePressed() {
  // Clickable controls are only shown/active during normal operation
  if (!isBaselineDone() || !isReceiverReady()) return;
  float mx = uiMouseX();
  float my = uiMouseY();
  if (isCalibrationButtonHit(mx, my)) {
    initBaseline();
    println("[TDF] Baseline recalibration triggered by Calibration button.");
    return;
  }
  handleMatrixMousePress(mx, my);   // sensor tabs + S/D toggle
  if (isResetViewButtonHit(mx, my)) {   // pressure-grid reset view
    resetPGView();
    return;
  }
  int rsi = rangeSliderHit(mx, my);     // axis-range sliders (X/Y/Z)
  if (rsi >= 0) {
    _rangeDragging = rsi;
    return;
  }
  if (isRangeLockHit(mx, my)) {         // XY lock toggle
    toggleRangeLock();
    return;
  }
  if (isRangeResetHit(mx, my)) {        // axis-ranges reset
    resetRanges();
    return;
  }
  if (isPlotSliderHit(mx, my)) {        // waveform points slider
    _spSliderDragging = true;
    return;
  }
  if (isPlotResetHit(mx, my)) {         // waveform points reset
    resetPlotPoints();
    return;
  }
  startPGDrag(mx, my);              // begin free orbit if press is in the pressure panel
}

void updateUILayout() {
  _uiScale = min(width / (float) DESIGN_W, height / (float) DESIGN_H);
  _uiOffsetX = (width - DESIGN_W * _uiScale) * 0.5;
  _uiOffsetY = (height - DESIGN_H * _uiScale) * 0.5;
}

void centerWindowOnScreen() {
  int x = max(0, (displayWidth - width) / 2);
  int y = max(0, (displayHeight - height) / 2);
  surface.setLocation(x, y);
}

float uiMouseX() {
  return (mouseX - _uiOffsetX) / _uiScale;
}

float uiMouseY() {
  return (mouseY - _uiOffsetY) / _uiScale;
}

float uiPMouseX() {
  return (pmouseX - _uiOffsetX) / _uiScale;
}

float uiPMouseY() {
  return (pmouseY - _uiOffsetY) / _uiScale;
}

// ============================================================
// drawNoConnection() — shown when serial port is unavailable
// ============================================================
void drawNoConnection() {
  int cx = DESIGN_W / 2;
  int cy = DESIGN_H / 2 - 30;

  textAlign(CENTER, CENTER);

  // --- 1. dot-grid background tint ---
  noStroke();
  int gridSpacingX = DESIGN_W / 9;
  int gridSpacingY = DESIGN_H / 6;
  for (int gx = gridSpacingX; gx < DESIGN_W; gx += gridSpacingX) {
    for (int gy = gridSpacingY; gy < DESIGN_H; gy += gridSpacingY) {
      fill(255, 60, 60, 18);
      ellipse(gx, gy, 4, 4);
    }
  }

  // --- 2. concentric pulse rings (4 rings, staggered phase) ---
  int[] ringR = { 50, 75, 100, 125 };
  noFill();
  strokeWeight(1.2);
  for (int i = 0; i < ringR.length; i++) {
    float phase = frameCount * 0.05 + i * HALF_PI;
    float alpha = map(sin(phase), -1, 1, 18, 100);
    stroke(255, 80, 70, alpha);
    ellipse(cx, cy, ringR[i] * 2, ringR[i] * 2);
  }
  noStroke();

  // --- 3. disconnect icon: X in circle ---
  noFill();
  strokeWeight(2);
  stroke(255, 110, 90);
  ellipse(cx, cy, 56, 56);
  strokeWeight(3);
  float d = 12;
  line(cx - d, cy - d, cx + d, cy + d);
  line(cx + d, cy - d, cx - d, cy + d);
  noStroke();

  // --- 5. main title with shadow ---
  textSize(32);
  String ellipsis = "...".substring(0, (int)(frameCount / 15) % 4);
  fill(120, 30, 20);
  text("No Connection" + ellipsis, cx + 1, cy + 151);   // shadow
  fill(255, 90, 80);
  text("No Connection" + ellipsis, cx, cy + 150);

  // --- 6. subtitle ---
  fill(160, 100, 100);
  textSize(13);
  text("No serial device detected.  Check cable and restart sketch.", cx, cy + 190);

  // --- 7. port list box ---
  String[] ports = Serial.list();
  if (ports.length > 0) {
    String portStr = "";
    for (int i = 0; i < ports.length; i++) {
      portStr += ports[i];
      if (i < ports.length - 1) portStr += "  |  ";
    }
    float boxW = textWidth(portStr) + 40;
    float boxH = 26;
    float boxX = cx - boxW / 2;
    float boxY = cy + 210;

    fill(45);
    strokeWeight(1);
    stroke(90);
    rect(boxX, boxY, boxW, boxH, 4);
    noStroke();

    fill(140);
    textSize(11);
    text(portStr, cx, boxY + boxH / 2);
  }

  // restore defaults
  textAlign(LEFT, BASELINE);
  textSize(14);
  noStroke();
  rectMode(CORNER);
}
