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

void setup() {
  size(1350, 940, P2D);
  surface.setLocation((displayWidth - 1350) / 2, (displayHeight - 940) / 2);
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

  updateReceiver();

  // --- serial not connected ---
  if (!isReceiverReady()) {
    drawNoConnection();
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
    return;
  }

  // --- compute decoupled force ---
  float dVx = sensorBx - baselineX;
  float dVy = sensorBy - baselineY;
  float dVz = sensorBz - baselineZ;
  computeForce(dVx, dVy, dVz);

  // --- header ---
  fill(180, 220, 255);
  text("Sensor: " + SENSOR_NAMES[activeSensor]
       + "   |   [M] Matrix   [1/2/3] Sensor   [T] S/D", 30, 30);

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
}

// ============================================================
// Input handlers
// ============================================================
void keyPressed() {
  handleMatrixKey(key);
}

void mouseDragged() {
  handleFVDrag();
  handlePGDrag();
}

// ============================================================
// drawNoConnection() — shown when serial port is unavailable
// ============================================================
void drawNoConnection() {
  int cx = width / 2;
  int cy = height / 2 - 30;

  textAlign(CENTER, CENTER);

  // --- 1. dot-grid background tint ---
  noStroke();
  int gridSpacingX = width / 9;
  int gridSpacingY = height / 6;
  for (int gx = gridSpacingX; gx < width; gx += gridSpacingX) {
    for (int gy = gridSpacingY; gy < height; gy += gridSpacingY) {
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
