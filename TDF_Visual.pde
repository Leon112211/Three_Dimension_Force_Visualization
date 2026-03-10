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
    fill(255, 80, 80);
    text("[ Serial port not connected ]  Check device and restart", 30, 40);
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
