// ============================================================
// MaterialPanel.pde
// Material-recognition result card (top of the right-hand column).
//
//   state badge  : WAITING / SENSING / RESULT
//   result       : material name + confidence (dimmed while sensing)
//   top-3 bars   : live class probabilities
//   recent       : last results as chips
//
// Classifier-agnostic API — whatever produces the verdict (demo, a Python
// model, the MCU) calls:
//   materialBeginContact()        a touch started        -> SENSING
//   materialUpdate(float[] p)     live probabilities (one per MATERIAL_NAMES)
//   materialCommit()              touch ended: argmax    -> RESULT + history
// Today only the demo source (DemoSource.pde) drives it.
// ============================================================

static final int MP_X = 1340;
static final int MP_Y = 30;
static final int MP_W = 360;
static final int MP_H = 160;   // same row as Sensor State / Matrix (y 30..190)

// Candidate materials, triboelectric series order (+ ... -). Replace freely.
static final String[] MATERIAL_NAMES = { "Nylon", "Skin", "Paper", "PET", "Silicone", "PTFE" };
static final int MP_HISTORY = 5;

static final int MP_WAITING = 0;
static final int MP_SENSING = 1;
static final int MP_RESULT  = 2;

int _mpState = MP_WAITING;
boolean _mpHasClassifier = false;            // set by the first API call
float[] mpProbs = new float[MATERIAL_NAMES.length];
int _mpResult = -1;                          // committed material index
float _mpConf = 0;
int[] _mpHist = new int[MP_HISTORY];         // newest first, -1 = empty
boolean[] _mpHistMiss = new boolean[MP_HISTORY];   // demo only: result != scripted truth

void initMaterialPanel() {
  clearMaterialPanel();
}

void clearMaterialPanel() {
  _mpState = MP_WAITING;
  _mpHasClassifier = false;
  _mpResult = -1;
  _mpConf = 0;
  for (int j = 0; j < mpProbs.length; j++) mpProbs[j] = 1.0 / mpProbs.length;
  for (int k = 0; k < MP_HISTORY; k++) {
    _mpHist[k] = -1;
    _mpHistMiss[k] = false;
  }
}

void materialBeginContact() {
  _mpHasClassifier = true;
  _mpState = MP_SENSING;
}

void materialUpdate(float[] p) {
  _mpHasClassifier = true;
  if (p == null || p.length != mpProbs.length) return;
  float sum = 0;
  for (int j = 0; j < p.length; j++) sum += max(0, p[j]);
  if (sum <= 0 || !isFiniteValue(sum)) return;
  for (int j = 0; j < p.length; j++) mpProbs[j] = max(0, p[j]) / sum;
}

void materialCommit() {
  materialCommitWithTruth(-1);
}

// truth >= 0 only from the demo, to mark chips the stand-in classifier got wrong.
void materialCommitWithTruth(int truth) {
  _mpHasClassifier = true;
  int best = materialArgmax();
  _mpResult = best;
  _mpConf = mpProbs[best];
  _mpState = MP_RESULT;
  for (int k = MP_HISTORY - 1; k > 0; k--) {
    _mpHist[k] = _mpHist[k - 1];
    _mpHistMiss[k] = _mpHistMiss[k - 1];
  }
  _mpHist[0] = best;
  _mpHistMiss[0] = truth >= 0 && truth != best;
}

int materialArgmax() {
  int best = 0;
  for (int j = 1; j < mpProbs.length; j++) if (mpProbs[j] > mpProbs[best]) best = j;
  return best;
}

// ============================================================
void drawMaterialPanel() {
  drawPanelBase(MP_X, MP_Y, MP_W, MP_H, "Material recognition");

  // state badge (top-right)
  String bl = _mpState == MP_SENSING ? "SENSING" : (_mpState == MP_RESULT ? "RESULT" : "WAITING");
  color bfg = _mpState == MP_SENSING ? UI_WARN : (_mpState == MP_RESULT ? UI_GOOD : UI_MUTED);
  color bbg = _mpState == MP_SENSING ? color(78, 51, 28)
            : (_mpState == MP_RESULT ? color(36, 92, 62) : color(64, 68, 78));
  useUIFont(11);
  float bw = textWidth(bl) + 18;
  drawBadge(MP_X + MP_W - 12 - bw, MP_Y + 6, bl, bbg, bfg);

  if (!_mpHasClassifier) {
    fill(UI_MUTED);
    useUIFont(13);
    textAlign(CENTER, CENTER);
    text("No classifier connected", MP_X + MP_W / 2.0, MP_Y + MP_H / 2.0 + 8);
    textAlign(LEFT, BASELINE);
    useUIFont(14);
    return;
  }

  // --- result line: committed result, or the live leader (dimmed) while sensing ---
  boolean sensing = _mpState == MP_SENSING;
  int shown = sensing ? materialArgmax() : _mpResult;
  float conf = sensing ? mpProbs[shown] : _mpConf;
  textAlign(LEFT, TOP);
  if (shown < 0 || (sensing && _mpResult < 0 && conf < 0.4)) {
    useUIFont(18);
    fill(UI_MUTED);
    text(sensing ? "Classifying..." : "Touch a material", MP_X + 16, MP_Y + 38);
  } else {
    color dim = color(150, 156, 170);
    useUIFont(24);
    fill(sensing ? dim : UI_TEXT);
    text(MATERIAL_NAMES[shown], MP_X + 16, MP_Y + 34);
    useMonoFont(20);
    textAlign(RIGHT, TOP);
    fill(sensing ? dim : UI_GOOD);
    text(round(conf * 100) + "%", MP_X + MP_W - 16, MP_Y + 34);
  }

  // --- top-3 probability bars ---
  int[] order = materialTopK(3);
  float barX = MP_X + 96, barW = MP_W - 96 - 58;
  for (int k = 0; k < order.length; k++) {
    int j = order[k];
    float y = MP_Y + 72 + k * 19;
    useUIFont(11);
    textAlign(LEFT, TOP);
    fill(UI_TEXT);
    text(MATERIAL_NAMES[j], MP_X + 16, y);
    noStroke();
    fill(UI_PANEL_HI);
    rect(barX, y + 1, barW, 11, 3);
    fill(k == 0 ? UI_T1 : color(75, 86, 112));
    rect(barX, y + 1, barW * mpProbs[j], 11, 3);
    useMonoFont(11);
    textAlign(RIGHT, TOP);
    fill(UI_MUTED);
    text(round(mpProbs[j] * 100) + "%", MP_X + MP_W - 16, y);
  }

  // --- recent results as chips ---
  float cy = MP_Y + MP_H - 26;
  useUIFont(11);
  textAlign(LEFT, CENTER);
  fill(UI_MUTED);
  text("recent", MP_X + 16, cy + 9);
  float cx = MP_X + 74;
  for (int k = 0; k < MP_HISTORY; k++) {
    if (_mpHist[k] < 0) break;
    String s = MATERIAL_NAMES[_mpHist[k]];
    float w = textWidth(s) + 14;
    if (cx + w > MP_X + MP_W - 12) break;
    noStroke();
    fill(UI_PANEL_HI);
    rect(cx, cy, w, 18, 9);
    fill(_mpHistMiss[k] ? UI_WARN : UI_TEXT);
    text(s, cx + 7, cy + 9);
    cx += w + 6;
  }

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

// Indices of the k most probable materials, highest first.
int[] materialTopK(int k) {
  k = min(k, mpProbs.length);
  int[] out = new int[k];
  boolean[] used = new boolean[mpProbs.length];
  for (int n = 0; n < k; n++) {
    int best = -1;
    for (int j = 0; j < mpProbs.length; j++) {
      if (!used[j] && (best < 0 || mpProbs[j] > mpProbs[best])) best = j;
    }
    used[best] = true;
    out[n] = best;
  }
  return out;
}
