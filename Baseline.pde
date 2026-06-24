// ============================================================
// Baseline.pde
// Collects valid Bx/By/Bz samples and computes the zero-force baseline.
// ============================================================

static final int BASELINE_SAMPLES = 100;

static final int BS_IDLE = 0;
static final int BS_SAMPLING = 1;
static final int BS_DONE = 2;

float baselineX = 0;
float baselineY = 0;
float baselineZ = 0;

int _bsState = BS_IDLE;
int _bsCount = 0;
int _bsSkippedFrames = 0;
float _bsAccumX = 0;
float _bsAccumY = 0;
float _bsAccumZ = 0;

void initBaseline() {
  _bsState = BS_SAMPLING;
  _bsCount = 0;
  _bsSkippedFrames = 0;
  _bsAccumX = 0;
  _bsAccumY = 0;
  _bsAccumZ = 0;
  baselineX = 0;
  baselineY = 0;
  baselineZ = 0;
  println("[Baseline] Sampling started (0/" + BASELINE_SAMPLES + ")");
}

void updateBaseline() {
  if (_bsState != BS_SAMPLING) return;

  if (!isCurrentSensorFrameFinite()) {
    _bsSkippedFrames++;
    if (_bsSkippedFrames <= 5 || _bsSkippedFrames % 25 == 0) {
      println("[Baseline] Skipped invalid sample during calibration ("
              + _bsSkippedFrames + " skipped). Check serial protocol or sensor output.");
    }
    return;
  }

  _bsAccumX += sensorBx;
  _bsAccumY += sensorBy;
  _bsAccumZ += sensorBz;
  _bsCount++;

  if (_bsCount >= BASELINE_SAMPLES) {
    baselineX = _bsAccumX / BASELINE_SAMPLES;
    baselineY = _bsAccumY / BASELINE_SAMPLES;
    baselineZ = _bsAccumZ / BASELINE_SAMPLES;

    if (!areFiniteValues(baselineX, baselineY, baselineZ)) {
      println("[Baseline] ERROR: computed a non-finite baseline; restart calibration.");
      initBaseline();
      return;
    }

    _bsState = BS_DONE;
    println("[Baseline] Done - Bx=" + nf(baselineX, 1, 4)
                              + "  By=" + nf(baselineY, 1, 4)
                              + "  Bz=" + nf(baselineZ, 1, 4) + "  (uT)");
  }
}

boolean isBaselineDone() {
  return _bsState == BS_DONE;
}

void drawBaselineHUD() {
  int panelW = 500;
  int panelH = 210;
  int px = (DESIGN_W - panelW) / 2;
  int py = (DESIGN_H - panelH) / 2;

  drawPanelBase(px, py, panelW, panelH, "");

  textAlign(CENTER, TOP);
  fill(UI_TEXT);
  useUIFont(15);
  text("Baseline Calibration - hold sensor steady", px + panelW / 2, py + 16);

  fill(UI_MUTED);
  useUIFont(12);
  text(_bsCount + " / " + BASELINE_SAMPLES + " valid samples", px + panelW / 2, py + 38);

  int barX = px + 50;
  int barW = panelW - 100;
  int barH = 18;
  int barGap = 38;
  int barStartY = py + 68;

  String[] labels = { "Bx", "By", "Bz" };
  color[] colors = { UI_X, UI_Y, UI_Z };

  float progress = (float) _bsCount / BASELINE_SAMPLES;

  for (int i = 0; i < 3; i++) {
    int barY = barStartY + i * barGap;

    fill(colors[i]);
    textSize(13);
    textAlign(RIGHT, CENTER);
    text(labels[i], barX - 8, barY + barH / 2);

    fill(UI_PANEL_HI);
    noStroke();
    rect(barX, barY, barW, barH, 4);

    fill(colors[i]);
    if (progress > 0) {
      rect(barX, barY, barW * progress, barH, 4);
    }

    fill(UI_TEXT);
    useMonoFont(11);
    textAlign(LEFT, CENTER);
    text(int(progress * 100) + "%", barX + barW + 6, barY + barH / 2);
  }

  if (_bsSkippedFrames > 0) {
    fill(UI_WARN);
    useUIFont(11);
    textAlign(CENTER, TOP);
    text("Skipped invalid samples: " + _bsSkippedFrames, px + panelW / 2, py + panelH - 28);
  }

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}
