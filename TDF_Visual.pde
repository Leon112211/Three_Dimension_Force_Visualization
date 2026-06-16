// ============================================================
// TDF_Visual.pde — Main entry
// Three-Dimensional Force Sensor Visualization
// Sensor models: H2 / H4 / H6
//
// Flow: Serial CSV → Baseline calibration → Decoupling F=D*dV → HUD
// Keyboard shortcuts:
//   [M]   Toggle matrix panel
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
}

void setup() {
  surface.setResizable(true);
  centerWindowOnScreen();
  textSize(14);
  textAlign(LEFT, BASELINE);

  initReceiver();     // SensorReceiver.pde
  initDecoupling();   // Decoupling.pde — build S and D matrices
  initForceView();    // ForceView.pde  — 3D arrows + bar chart
  initPressureGrid(); // PressureGrid.pde — Z-axis pressure surface
  initCompass();      // TangentialCompass.pde — XY force compass
  initPlot();         // SensorPlot.pde  — real-time Bx/By/Bz waveform
  initBaseline();     // Baseline.pde   — begin 300-sample calibration
}

void draw() {
  background(30);
  updateUILayout();
  pushMatrix();
  translate(_uiOffsetX, _uiOffsetY);
  scale(_uiScale);

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

  // --- header ---
  fill(180, 220, 255);
  text("Sensor: " + SENSOR_NAMES[activeSensor]
       + "   |   [M] Matrix   [1/2/3] Sensor   [T] S/D   [C] Recalibrate", 30, 30);

  // --- magnetic field readout ---
  int col1 = 30;
  int col2 = 280;
  int rowY = 60;
  int rowH = 26;

  fill(100, 160, 220);
  textSize(12);
  text("Magnetic field (uT)", col1, rowY);
  text("Decoupled force (N)", col2, rowY);

  textSize(14);
  color dataColor = newDataAvailable ? color(100, 255, 150) : color(160);
  fill(dataColor);

  // Bx / dBx / Fx
  rowY += rowH;
  text("Bx=" + nf(sensorBx, 1, 3) + "  dBx=" + nf(dVx, 1, 3), col1, rowY);
  text("Fx = " + nf(forceX, 1, 4) + " N", col2, rowY);

  // By / dBy / Fy
  rowY += rowH;
  text("By=" + nf(sensorBy, 1, 3) + "  dBy=" + nf(dVy, 1, 3), col1, rowY);
  text("Fy = " + nf(forceY, 1, 4) + " N", col2, rowY);

  // Bz / dBz / Fz
  rowY += rowH;
  text("Bz=" + nf(sensorBz, 1, 3) + "  dBz=" + nf(dVz, 1, 3), col1, rowY);
  text("Fz = " + nf(forceZ, 1, 4) + " N", col2, rowY);

  // --- baseline reference ---
  rowY += rowH + 6;
  fill(90);
  textSize(11);
  text("Baseline  Bx=" + nf(baselineX,1,3)
       + "  By=" + nf(baselineY,1,3)
       + "  Bz=" + nf(baselineZ,1,3), col1, rowY);
  if (receiverBadFrameCount() > 0) {
    rowY += rowH;
    fill(255, 160, 80);
    text("Skipped invalid serial frames: " + receiverBadFrameCount(), col1, rowY);
  }
  textSize(14);

  newDataAvailable = false;

  // --- 3D force view + bar chart ---
  drawForceView();

  // --- Z-axis pressure surface ---
  drawPressureGrid();

  // --- XY tangential force compass ---
  drawCompass(forceX, forceY);

  // --- real-time sensor waveform ---
  drawPlot();

  // --- interactive matrix overlay (on top of everything) ---
  drawMatrixHUD();

  popMatrix();
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
  handleFVDrag();
  handlePGDrag();
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
