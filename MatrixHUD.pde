// ============================================================
// MatrixHUD.pde
// Interactive overlay for viewing sensitivity (S) and
// decoupling (D) matrices of each sensor.
//
// Toggle:  press 'M' to show / hide the matrix panel
// Switch:  press '1' / '2' / '3' to select H2 / H4 / H6
// Tab:     press 'T' to toggle between S and D view
//
// Public API (called from TDF_Visual):
//   drawMatrixHUD()     — render if visible
//   handleMatrixKey(key) — forward keyPressed events
// ============================================================

boolean _matrixVisible = false;
boolean _showDecoupling = false;   // false = S, true = D

// ============================================================
void drawMatrixHUD() {
  if (!_matrixVisible) return;

  int panelW = 440;
  int panelH = 260;
  int px = width - panelW - 20;
  int py = 20;

  // --- background ---
  fill(15, 15, 25, 230);
  noStroke();
  rect(px, py, panelW, panelH, 8);

  stroke(80, 130, 220, 140);
  strokeWeight(1);
  noFill();
  rect(px, py, panelW, panelH, 8);
  noStroke();

  // --- title bar ---
  String matType  = _showDecoupling ? "D  (N/uT)" : "S  (uT/N)";
  String sensorName = SENSOR_NAMES[activeSensor];

  textAlign(CENTER, TOP);
  fill(180, 220, 255);
  textSize(14);
  text(sensorName + "  —  " + matType, px + panelW/2, py + 12);

  // --- sensor tabs ---
  int tabW = 52;
  int tabH = 22;
  int tabY = py + 36;
  int tabStartX = px + (panelW - NUM_SENSORS * (tabW + 8)) / 2;

  for (int i = 0; i < NUM_SENSORS; i++) {
    int tx = tabStartX + i * (tabW + 8);
    if (i == activeSensor) {
      fill(80, 140, 255);
    } else {
      fill(50, 55, 70);
    }
    noStroke();
    rect(tx, tabY, tabW, tabH, 4);

    fill(i == activeSensor ? 255 : 160);
    textSize(12);
    textAlign(CENTER, CENTER);
    text(SENSOR_NAMES[i], tx + tabW/2, tabY + tabH/2);
  }

  // --- S / D toggle ---
  int togW = 56;
  int togH = 22;
  int togX = px + panelW - togW - 16;
  int togY = tabY;

  fill(_showDecoupling ? color(220, 140, 60) : color(80, 180, 120));
  noStroke();
  rect(togX, togY, togW, togH, 4);

  fill(255);
  textSize(11);
  textAlign(CENTER, CENTER);
  text(_showDecoupling ? "D" : "S", togX + togW/2, togY + togH/2);

  // --- matrix grid ---
  float[][] mat = _showDecoupling ? D_ALL[activeSensor] : S_ALL[activeSensor];
  int gridX = px + 36;
  int gridY = tabY + tabH + 20;
  int cellW = 110;
  int cellH = 30;

  String[] axisLabels = { "Bx", "By", "Bz" };
  String[] forceLabels = { "Fx", "Fy", "Fz" };
  if (_showDecoupling) {
    axisLabels  = new String[] { "Fx", "Fy", "Fz" };
    forceLabels = new String[] { "Bx", "By", "Bz" };
  }

  // column headers
  textSize(11);
  fill(140, 180, 220);
  textAlign(CENTER, CENTER);
  for (int c = 0; c < 3; c++) {
    text(forceLabels[c], gridX + 40 + c * cellW + cellW/2, gridY - 10);
  }

  // rows
  for (int r = 0; r < 3; r++) {
    int ry = gridY + r * cellH;

    // row label
    fill(140, 180, 220);
    textSize(11);
    textAlign(RIGHT, CENTER);
    text(axisLabels[r], gridX + 30, ry + cellH/2);

    for (int c = 0; c < 3; c++) {
      int cx = gridX + 40 + c * cellW;
      float val = mat[r][c];

      // cell background
      if (r == c) {
        fill(40, 60, 90, 180);  // diagonal highlight
      } else {
        fill(30, 35, 50, 150);
      }
      noStroke();
      rect(cx, ry, cellW - 4, cellH - 4, 3);

      // value text — color negative values differently
      if (val < 0) {
        fill(255, 120, 100);
      } else {
        fill(200, 240, 200);
      }
      textSize(13);
      textAlign(CENTER, CENTER);
      if (_showDecoupling) {
        text(nf(val, 1, 6), cx + (cellW-4)/2, ry + (cellH-4)/2);
      } else {
        text(nf(val, 1, 2), cx + (cellW-4)/2, ry + (cellH-4)/2);
      }
    }
  }

  // --- help hint ---
  fill(100);
  textSize(10);
  textAlign(CENTER, TOP);
  text("[M] hide    [1/2/3] sensor    [T] toggle S/D", px + panelW/2, py + panelH - 20);

  // reset text state
  textAlign(LEFT, BASELINE);
  textSize(14);
}

// ============================================================
// handleMatrixKey() — call from keyPressed()
// ============================================================
void handleMatrixKey(char k) {
  if (k == 'm' || k == 'M') {
    _matrixVisible = !_matrixVisible;
  }
  if (k == 't' || k == 'T') {
    _showDecoupling = !_showDecoupling;
  }
  if (k == '1') selectSensor(0);
  if (k == '2') selectSensor(1);
  if (k == '3') selectSensor(2);
}
