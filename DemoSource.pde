// ============================================================
// DemoSource.pde
// Simulated data source (CONN_DEMO) — preview the full UI without a sensor.
//
// Each draw frame synthesizes one magnetic-field frame
//   B = DEMO_B0 + S * F(t) + noise
// and feeds it through acceptFrame(), so the real pipeline (baseline,
// F = D * dB, every panel) runs unchanged and D = S^-1 recovers F(t).
//
// F(t) is a 12 s loop of three 4 s segments; each is a 3 s touch (starting and
// ending at 0 N) followed by 1 s of rest, so the material verdict stays visible:
//   0-4 s  press     : Fz rises to 12 N and releases
//   4-8 s  slide     : light Fz + Fx/Fy sweeping a circle
//   8-12 s combined  : pulsing Fz + oscillating Fx
//
// TENG channels (TengPanel.pde) are derived from the same F(t): output ~ rate
// of contact change, so a press gives a +pulse, a release a -pulse, and a slide
// lights the quadrant electrodes in rotation:
//   v_i = K1 * q_m * w_i * dFz/dt + K2 * d(Fxy . u_i)/dt + noise
//
// Material recognition (MaterialPanel.pde): every 4 s segment is one touch with
// a scripted material m (cycling MATERIAL_NAMES); its charge affinity q_m sets
// the polarity/size of the press pulse. A stand-in classifier (demoClassify)
// estimates q from the pulses and feeds the card's public API — it is NOT a
// trained model, just enough to make the card behave realistically.
// ============================================================

static final float DEMO_B0_X = -120;      // simulated zero-force field (uT)
static final float DEMO_B0_Y = 35;
static final float DEMO_B0_Z = -480;
static final float DEMO_NOISE_UT = 0.3;   // per-channel Gaussian noise (uT)
static final float DEMO_SEGMENT_S = 4.0;  // seconds per segment (3 segments)
static final float DEMO_TOUCH_FRAC = 0.75; // touch part of each segment; the rest is idle

int _demoT0 = 0;                // millis() when the force animation (re)started
boolean _demoWarnedZeroD = false;

static final float DEMO_TENG_K1 = 0.13;     // V per (N/s) of dFz/dt
static final float DEMO_TENG_K2 = 0.55;     // V per (N/s) of tangential motion
static final float DEMO_TENG_NOISE = 0.03;  // V
// Outward unit direction of each quadrant electrode (T1 TL, T2 TR, T3 BL, T4 BR)
static final float[] DEMO_TENG_UX = { -0.7071,  0.7071, -0.7071, 0.7071 };
static final float[] DEMO_TENG_UY = {  0.7071,  0.7071, -0.7071, -0.7071 };
static final float[] DEMO_TENG_W  = { 1.00, 0.92, 1.08, 0.96 };   // slight per-channel gain spread
float _demoPrevFx = 0, _demoPrevFy = 0, _demoPrevFz = 0;
int _demoPrevMs = -1;

// charge affinity per MATERIAL_NAMES entry (+ = tends to lose electrons)
static final float[] DEMO_MAT_Q = { 1.0, 0.65, 0.25, -0.3, -0.7, -1.0 };
float _demoLastDfz = 0;          // last frame's dFz/dt (N/s)
float _demoLastVSum = 0;         // last frame's sum of the 4 TENG channels (V)
boolean _demoTouching = false;   // demo classifier: inside a touch
float _demoQSum = 0;             // accumulated q estimates for this touch
int _demoQN = 0;

void startDemo() {
  resetReceiverState();
  connMode = CONN_DEMO;
  _demoT0 = millis();
  _demoWarnedZeroD = false;
  _demoPrevFx = 0;
  _demoPrevFy = 0;
  _demoPrevFz = 0;
  _demoPrevMs = -1;
  _demoTouching = false;
  initBaseline();    // the real calibration screen runs on the simulated frames
  println("[Connection] Source = DEMO (simulated data, no sensor)");
}

// Called once per draw frame from updateConnection().
void updateDemo() {
  float fx = 0, fy = 0, fz = 0;
  int mat = 0;   // scripted material of the current touch

  if (!isBaselineDone()) {
    // 标定期间保持零力，并不断重置时钟：重新标定后动画从头开始
    _demoT0 = millis();
  } else {
    float t = ((millis() - _demoT0) / 1000.0) % (3 * DEMO_SEGMENT_S);
    int seg = (int) (t / DEMO_SEGMENT_S);
    float u = (t - seg * DEMO_SEGMENT_S) / (DEMO_SEGMENT_S * DEMO_TOUCH_FRAC);   // 0..1 = touch, >1 = rest
    float env = u < 1 ? sin(PI * u) : 0;                       // 0 at both ends, 0 while resting
    if (u >= 1) u = 0;
    int touch = (int) ((millis() - _demoT0) / (DEMO_SEGMENT_S * 1000));   // absolute segment count
    mat = touch % MATERIAL_NAMES.length;

    if (seg == 0) {          // press
      fz = 12.0 * env * env;
    } else if (seg == 1) {   // slide: circle on the compass under light load
      fz = 3.0 * env;
      fx = 1.5 * env * cos(TWO_PI * u);
      fy = 1.5 * env * sin(TWO_PI * u);
    } else {                 // combined
      fz = 8.0 * env * (0.6 + 0.4 * sin(3 * TWO_PI * u));
      fx = 1.0 * env * sin(2 * TWO_PI * u);
    }
  }

  // B = B0 + S * F (+ noise) with the active sensor's S, so switching
  // H2/H4/H6 keeps the displayed force identical.
  float[][] S = S_ALL[activeSensor];
  float bx = DEMO_B0_X + S[0][0] * fx + S[0][1] * fy + S[0][2] * fz
             + randomGaussian() * DEMO_NOISE_UT;
  float by = DEMO_B0_Y + S[1][0] * fx + S[1][1] * fy + S[1][2] * fz
             + randomGaussian() * DEMO_NOISE_UT;
  float bz = DEMO_B0_Z + S[2][0] * fx + S[2][1] * fy + S[2][2] * fz
             + randomGaussian() * DEMO_NOISE_UT;

  if (!_demoWarnedZeroD && isZeroMatrix(D_ALL[activeSensor])) {
    println("[Demo] WARNING: " + SENSOR_NAMES[activeSensor]
            + " has no valid D matrix; decoupled force will read 0.");
    _demoWarnedZeroD = true;
  }

  acceptFrame(bx, by, bz, false);   // never recorded to CSV
  pushDemoTeng(fx, fy, fz, DEMO_MAT_Q[mat]);
  demoClassify(fz, mat);
}

// Stand-in classifier: q-hat = sum(v) / (K1 * dFz/dt * sum(w)) while pressing
// (the tangential term cancels across the 4 symmetric electrodes), then a
// Gaussian score per material that sharpens as samples accumulate.
void demoClassify(float fz, int truth) {
  if (!_demoTouching && fz > 0.8) {
    _demoTouching = true;
    _demoQSum = 0;
    _demoQN = 0;
    for (int j = 0; j < mpProbs.length; j++) mpProbs[j] = 1.0 / mpProbs.length;
    materialBeginContact();
  }
  if (!_demoTouching) return;

  if (_demoLastDfz > 1.5) {
    float wSum = 0;
    for (int c = 0; c < TENG_N; c++) wSum += DEMO_TENG_W[c];
    float qHat = _demoLastVSum / (DEMO_TENG_K1 * _demoLastDfz * wSum)
                 + randomGaussian() * 0.25;   // sensor/model uncertainty
    _demoQSum += qHat;
    _demoQN++;
  }
  if (_demoQN > 0) {
    float qm = _demoQSum / _demoQN;
    float sig2 = 0.06 + 0.4 / (1 + _demoQN);   // floor keeps neighbours plausible (~80% conf)
    float[] p = new float[MATERIAL_NAMES.length];
    for (int j = 0; j < p.length; j++) {
      float d = DEMO_MAT_Q[j] - qm;
      float score = exp(-d * d / sig2);
      p[j] = 0.85 * mpProbs[j] + 0.15 * score;   // smoothed toward the new scores
    }
    materialUpdate(p);   // normalizes
  }

  if (fz < 0.3) {   // touch released
    _demoTouching = false;
    materialCommitWithTruth(truth);
  }
}

// Synthesize the 4 TENG channels from the force's rate of change.
void pushDemoTeng(float fx, float fy, float fz, float q) {
  int now = millis();
  float dt = _demoPrevMs < 0 ? 0 : (now - _demoPrevMs) / 1000.0;
  float dfz = 0, dfx = 0, dfy = 0;
  if (dt > 0) {
    dfz = (fz - _demoPrevFz) / dt;
    dfx = (fx - _demoPrevFx) / dt;
    dfy = (fy - _demoPrevFy) / dt;
  }
  float[] v = new float[TENG_N];
  for (int c = 0; c < TENG_N; c++) {
    float dproj = dfx * DEMO_TENG_UX[c] + dfy * DEMO_TENG_UY[c];
    v[c] = DEMO_TENG_K1 * q * DEMO_TENG_W[c] * dfz + DEMO_TENG_K2 * dproj
           + randomGaussian() * DEMO_TENG_NOISE;
  }
  pushTengFrame(v[0], v[1], v[2], v[3]);
  _demoLastDfz = dfz;
  _demoLastVSum = v[0] + v[1] + v[2] + v[3];
  _demoPrevFx = fx;
  _demoPrevFy = fy;
  _demoPrevFz = fz;
  _demoPrevMs = now;
}

boolean isZeroMatrix(float[][] m) {
  for (int r = 0; r < 3; r++)
    for (int c = 0; c < 3; c++)
      if (m[r][c] != 0) return false;
  return true;
}
