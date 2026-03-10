// ============================================================
// Baseline.pde
// Collects 300 simultaneous samples of Bx/By/Bz and computes
// the mean of each as the zero-force baseline.
// All three axes accumulate in parallel — one sample per frame.
//
// Public API:
//   initBaseline()     — call in setup()
//   updateBaseline()   — call in draw() when newDataAvailable
//   isBaselineDone()   — returns true after 300 samples collected
//   drawBaselineHUD()  — renders 3 progress bars while sampling
//
// After done, read:
//   baselineX / baselineY / baselineZ  (float, uT)
// ============================================================

static final int BASELINE_SAMPLES = 300;

static final int BS_IDLE    = 0;
static final int BS_SAMPLING = 1;
static final int BS_DONE    = 2;

// --- results ---
float baselineX = 0;
float baselineY = 0;
float baselineZ = 0;

// --- internal ---
int   _bsState  = BS_IDLE;
int   _bsCount  = 0;
float _bsAccumX = 0;
float _bsAccumY = 0;
float _bsAccumZ = 0;

// ============================================================
void initBaseline() {
  _bsState  = BS_SAMPLING;
  _bsCount  = 0;
  _bsAccumX = 0;
  _bsAccumY = 0;
  _bsAccumZ = 0;
  println("[Baseline] Sampling started (0/" + BASELINE_SAMPLES + ")");
}

// ============================================================
// Call once per new data frame while !isBaselineDone()
// ============================================================
void updateBaseline() {
  if (_bsState != BS_SAMPLING) return;

  _bsAccumX += sensorBx;
  _bsAccumY += sensorBy;
  _bsAccumZ += sensorBz;
  _bsCount++;

  if (_bsCount >= BASELINE_SAMPLES) {
    baselineX = _bsAccumX / BASELINE_SAMPLES;
    baselineY = _bsAccumY / BASELINE_SAMPLES;
    baselineZ = _bsAccumZ / BASELINE_SAMPLES;
    _bsState  = BS_DONE;
    println("[Baseline] Done — Bx=" + nf(baselineX,1,4)
                              + "  By=" + nf(baselineY,1,4)
                              + "  Bz=" + nf(baselineZ,1,4) + "  (uT)");
  }
}

// ============================================================
boolean isBaselineDone() {
  return _bsState == BS_DONE;
}

// ============================================================
// drawBaselineHUD()
// Centered overlay with three parallel progress bars.
// ============================================================
void drawBaselineHUD() {
  int panelW = 500;
  int panelH = 210;
  int px     = (width  - panelW) / 2;
  int py     = (height - panelH) / 2;

  // background panel
  fill(20, 20, 30, 220);
  noStroke();
  rect(px, py, panelW, panelH, 10);

  // border
  stroke(100, 160, 255, 160);
  strokeWeight(1.5);
  noFill();
  rect(px, py, panelW, panelH, 10);
  strokeWeight(1);
  noStroke();

  // title
  textAlign(CENTER, TOP);
  fill(180, 220, 255);
  textSize(15);
  text("Baseline Calibration — hold sensor steady", px + panelW/2, py + 16);

  // sample counter
  fill(160);
  textSize(12);
  text(_bsCount + " / " + BASELINE_SAMPLES + " samples", px + panelW/2, py + 38);

  // three bars
  int barX = px + 50;
  int barW = panelW - 100;
  int barH = 18;
  int barGap = 38;
  int barStartY = py + 68;

  String[] labels = { "Bx", "By", "Bz" };
  color[]  colors = { color(80, 140, 255), color(100, 220, 100), color(255, 160, 60) };

  float progress = (float) _bsCount / BASELINE_SAMPLES;

  for (int i = 0; i < 3; i++) {
    int barY = barStartY + i * barGap;

    // axis label
    fill(colors[i]);
    textSize(13);
    textAlign(RIGHT, CENTER);
    text(labels[i], barX - 8, barY + barH / 2);

    // track
    fill(50, 50, 70);
    noStroke();
    rect(barX, barY, barW, barH, 4);

    // filled portion
    fill(colors[i]);
    if (progress > 0) {
      rect(barX, barY, barW * progress, barH, 4);
    }

    // percentage text inside/after bar
    fill(220);
    textSize(11);
    textAlign(LEFT, CENTER);
    text(nf(progress * 100, 1, 0) + "%", barX + barW + 6, barY + barH / 2);
  }

  // reset text state
  textAlign(LEFT, BASELINE);
  textSize(14);
  noStroke();
}
