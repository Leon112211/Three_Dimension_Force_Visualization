// ============================================================
// MatrixHUD.pde
// Compact overlay for sensitivity (S) and decoupling (D) matrices.
// ============================================================

boolean _showDecoupling = false;

// --- MatrixHUD layout (design coords; shared by draw + click hit-test) ---
static final int MX_PANEL_W = 450;
static final int MX_PANEL_H = 160;
static final int MX_PX = DESIGN_W - MX_PANEL_W - 30;
static final int MX_PY = 30;
static final int MX_TAB_W = 52;
static final int MX_TAB_H = 22;
static final int MX_TAB_GAP = 8;
static final int MX_TAB_Y = MX_PY + 32;
static final int MX_TAB_START_X = MX_PX + (MX_PANEL_W - NUM_SENSORS * (MX_TAB_W + MX_TAB_GAP)) / 2;
static final int MX_TOG_W = 56;
static final int MX_TOG_H = 22;
static final int MX_TOG_X = MX_PX + MX_PANEL_W - MX_TOG_W - 16;
static final int MX_TOG_Y = MX_TAB_Y;

void drawMatrixHUD() {
  drawPanelBase(MX_PX, MX_PY, MX_PANEL_W, MX_PANEL_H, _showDecoupling ? "D (N/uT)" : "S (uT/N)");

  // sensor tabs (clickable) + S/D toggle (clickable) — see handleMatrixMousePress
  float mx = uiMouseX();
  float my = uiMouseY();

  for (int i = 0; i < NUM_SENSORS; i++) {
    int tx = MX_TAB_START_X + i * (MX_TAB_W + MX_TAB_GAP);
    boolean tabHover = matrixTabHit(i, mx, my);
    fill(i == activeSensor ? UI_BORDER_ACTIVE : (tabHover ? UI_BORDER : UI_PANEL_HI));
    rect(tx, MX_TAB_Y, MX_TAB_W, MX_TAB_H, 4);

    fill(i == activeSensor ? UI_TEXT : UI_MUTED);
    useUIFont(12);
    textAlign(CENTER, CENTER);
    text(SENSOR_NAMES[i], tx + MX_TAB_W / 2, MX_TAB_Y + MX_TAB_H / 2);
  }

  boolean togHover = matrixToggleHit(mx, my);
  color togBase = _showDecoupling ? color(128, 83, 43) : color(37, 100, 70);
  fill(togHover ? lerpColor(togBase, color(255), 0.18f) : togBase);
  rect(MX_TOG_X, MX_TOG_Y, MX_TOG_W, MX_TOG_H, 4);
  fill(UI_TEXT);
  useUIFont(11);
  textAlign(CENTER, CENTER);
  text(_showDecoupling ? "D" : "S", MX_TOG_X + MX_TOG_W / 2, MX_TOG_Y + MX_TOG_H / 2);

  float[][] mat = _showDecoupling ? D_ALL[activeSensor] : S_ALL[activeSensor];
  int gridX = MX_PX + 36;
  int gridY = MX_TAB_Y + MX_TAB_H + 17;
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

// --- Mouse equivalents of the keyboard shortcuts (clickable tabs/toggle) ---
boolean matrixTabHit(int i, float mx, float my) {
  int tx = MX_TAB_START_X + i * (MX_TAB_W + MX_TAB_GAP);
  return mx >= tx && mx <= tx + MX_TAB_W &&
         my >= MX_TAB_Y && my <= MX_TAB_Y + MX_TAB_H;
}

boolean matrixToggleHit(float mx, float my) {
  return mx >= MX_TOG_X && mx <= MX_TOG_X + MX_TOG_W &&
         my >= MX_TOG_Y && my <= MX_TOG_Y + MX_TOG_H;
}

// Click H2/H4/H6 tab -> select sensor (same as [1/2/3]);
// click S/D toggle -> toggle view (same as [T]).
void handleMatrixMousePress(float mx, float my) {
  for (int i = 0; i < NUM_SENSORS; i++) {
    if (matrixTabHit(i, mx, my)) {
      selectSensor(i);
      return;
    }
  }
  if (matrixToggleHit(mx, my)) {
    _showDecoupling = !_showDecoupling;
  }
}
