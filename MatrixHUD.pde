// ============================================================
// MatrixHUD.pde
// Compact overlay for sensitivity (S) and decoupling (D) matrices.
// ============================================================

boolean _showDecoupling = false;

void drawMatrixHUD() {
  int panelW = 450;
  int panelH = 160;
  int px = DESIGN_W - panelW - 30;
  int py = 30;

  noStroke();
  fill(0, 0, 0, 80);
  rect(px + 2, py + 3, panelW, panelH, 8);
  fill(UI_PANEL, 238);
  rect(px, py, panelW, panelH, 8);

  stroke(UI_BORDER_ACTIVE, 180);
  strokeWeight(1);
  noFill();
  rect(px + 0.5, py + 0.5, panelW - 1, panelH - 1, 8);
  noStroke();

  String matType = _showDecoupling ? "D  (N/uT)" : "S  (uT/N)";
  textAlign(CENTER, TOP);
  fill(UI_TEXT);
  useUIFont(13);
  text(SENSOR_NAMES[activeSensor] + "   " + matType, px + panelW / 2, py + 9);

  int tabW = 52;
  int tabH = 22;
  int tabY = py + 32;
  int tabStartX = px + (panelW - NUM_SENSORS * (tabW + 8)) / 2;

  for (int i = 0; i < NUM_SENSORS; i++) {
    int tx = tabStartX + i * (tabW + 8);
    fill(i == activeSensor ? UI_BORDER_ACTIVE : UI_PANEL_HI);
    rect(tx, tabY, tabW, tabH, 4);

    fill(i == activeSensor ? UI_TEXT : UI_MUTED);
    useUIFont(12);
    textAlign(CENTER, CENTER);
    text(SENSOR_NAMES[i], tx + tabW / 2, tabY + tabH / 2);
  }

  int togW = 56;
  int togH = 22;
  int togX = px + panelW - togW - 16;
  int togY = tabY;
  fill(_showDecoupling ? color(128, 83, 43) : color(37, 100, 70));
  rect(togX, togY, togW, togH, 4);
  fill(UI_TEXT);
  useUIFont(11);
  textAlign(CENTER, CENTER);
  text(_showDecoupling ? "D" : "S", togX + togW / 2, togY + togH / 2);

  float[][] mat = _showDecoupling ? D_ALL[activeSensor] : S_ALL[activeSensor];
  int gridX = px + 36;
  int gridY = tabY + tabH + 17;
  int cellW = 104;
  int cellH = 24;

  String[] axisLabels = { "Bx", "By", "Bz" };
  String[] forceLabels = { "Fx", "Fy", "Fz" };
  if (_showDecoupling) {
    axisLabels = new String[] { "Fx", "Fy", "Fz" };
    forceLabels = new String[] { "Bx", "By", "Bz" };
  }

  useUIFont(10);
  fill(UI_MUTED);
  textAlign(CENTER, CENTER);
  for (int c = 0; c < 3; c++) {
    text(forceLabels[c], gridX + 40 + c * cellW + cellW / 2, gridY - 9);
  }

  for (int r = 0; r < 3; r++) {
    int ry = gridY + r * cellH;
    fill(UI_MUTED);
    useUIFont(10);
    textAlign(RIGHT, CENTER);
    text(axisLabels[r], gridX + 30, ry + cellH / 2);

    for (int c = 0; c < 3; c++) {
      int cx = gridX + 40 + c * cellW;
      float val = mat[r][c];

      fill(r == c ? color(38, 55, 80, 210) : color(23, 28, 40, 210));
      rect(cx, ry, cellW - 4, cellH - 4, 3);

      fill(val < 0 ? UI_DANGER : color(184, 226, 196));
      useMonoFont(12);
      textAlign(CENTER, CENTER);
      if (_showDecoupling) {
        text(nf(val, 1, 5), cx + (cellW - 4) / 2, ry + (cellH - 4) / 2);
      } else {
        text(nf(val, 1, 2), cx + (cellW - 4) / 2, ry + (cellH - 4) / 2);
      }
    }
  }

  textAlign(LEFT, BASELINE);
  useUIFont(14);
}

void handleMatrixKey(char k) {
  if (k == 't' || k == 'T') {
    _showDecoupling = !_showDecoupling;
  }
  if (k == '1') selectSensor(0);
  if (k == '2') selectSensor(1);
  if (k == '3') selectSensor(2);
}
