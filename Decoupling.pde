// ============================================================
// Decoupling.pde
// Stores the pre-computed sensitivity matrices S and decoupling
// matrices D = S^-1 for each sensor model (H2, H4, H6).
// Provides real-time force computation: F = D * dV
//   where dV = [Bx-baselineX, By-baselineY, Bz-baselineZ]
//
// Public API:
//   initDecoupling()                  — call in setup()
//   selectSensor(int index)           — 0=H2, 1=H4, 2=H6
//   computeForce(float dVx, dVy, dVz) — writes forceX/Y/Z
//
// Global outputs (updated every call to computeForce):
//   forceX / forceY / forceZ  (float, N)
//
// Data reference accessible for MatrixHUD:
//   SENSOR_NAMES[], S_ALL[][], D_ALL[][]
// ============================================================

static final int NUM_SENSORS = 3;
static final String[] SENSOR_NAMES = { "H2", "H4", "H6" };

// Sensitivity matrices S  (uT/N)  —  rows = Bx/By/Bz, cols = Fx/Fy/Fz
// Decoupling matrices D  (N/uT)  —  D = S^-1

// S[sensor][row][col],  D[sensor][row][col]
float[][][] S_ALL = new float[NUM_SENSORS][3][3];
float[][][] D_ALL = new float[NUM_SENSORS][3][3];

int   activeSensor = 0;       // currently selected sensor index
float forceX = 0, forceY = 0, forceZ = 0;

// ============================================================
void initDecoupling() {
  // ---------- H2 ----------
  // S rows: Bx, By, Bz;  cols: Fx, Fy, Fz
  S_ALL[0] = new float[][] {
    {  1,  8,  6 },   // Bx
    {  4,  2,  9 },   // By
    {  7,  5,  3 }    // Bz
  };

  // ---------- H4 ----------
  S_ALL[1] = new float[][] {
    {  12,  89,  67 },
    {  45,  23,  90 },
    {  78,  56,  34 }
  };

  // ---------- H6 ----------
  S_ALL[2] = new float[][] {
    {  11,  88,  66 },
    {  44,  22,  99 },
    {  77,  55,  33 }
  };

  // compute D = S^-1 for each sensor
  for (int s = 0; s < NUM_SENSORS; s++) {
    D_ALL[s] = invert3x3(S_ALL[s]);
    if (D_ALL[s] == null) {
      println("[Decoupling] WARNING: " + SENSOR_NAMES[s] + " matrix is singular!");
      D_ALL[s] = new float[3][3];  // zero matrix fallback
    } else {
      println("[Decoupling] " + SENSOR_NAMES[s]
              + " D computed. det(S) = " + nf(det3x3(S_ALL[s]), 1, 2));
    }
  }

  selectSensor(0);
}

// ============================================================
void selectSensor(int index) {
  activeSensor = constrain(index, 0, NUM_SENSORS - 1);
  println("[Decoupling] Active sensor: " + SENSOR_NAMES[activeSensor]);
}

// ============================================================
// computeForce()  — F = D * dV
// dVx/dVy/dVz = sensor reading minus baseline (uT)
// ============================================================
void computeForce(float dVx, float dVy, float dVz) {
  float[][] D = D_ALL[activeSensor];
  forceX = D[0][0] * dVx + D[0][1] * dVy + D[0][2] * dVz;
  forceY = D[1][0] * dVx + D[1][1] * dVy + D[1][2] * dVz;
  forceZ = D[2][0] * dVx + D[2][1] * dVy + D[2][2] * dVz;
}

// ============================================================
// 3x3 matrix utilities
// ============================================================

float det3x3(float[][] m) {
  return m[0][0] * (m[1][1]*m[2][2] - m[1][2]*m[2][1])
       - m[0][1] * (m[1][0]*m[2][2] - m[1][2]*m[2][0])
       + m[0][2] * (m[1][0]*m[2][1] - m[1][1]*m[2][0]);
}

// Returns null if singular
float[][] invert3x3(float[][] m) {
  float det = det3x3(m);
  if (abs(det) < 1e-12) return null;

  float invDet = 1.0 / det;
  float[][] r = new float[3][3];

  r[0][0] =  (m[1][1]*m[2][2] - m[1][2]*m[2][1]) * invDet;
  r[0][1] = -(m[0][1]*m[2][2] - m[0][2]*m[2][1]) * invDet;
  r[0][2] =  (m[0][1]*m[1][2] - m[0][2]*m[1][1]) * invDet;

  r[1][0] = -(m[1][0]*m[2][2] - m[1][2]*m[2][0]) * invDet;
  r[1][1] =  (m[0][0]*m[2][2] - m[0][2]*m[2][0]) * invDet;
  r[1][2] = -(m[0][0]*m[1][2] - m[0][2]*m[1][0]) * invDet;

  r[2][0] =  (m[1][0]*m[2][1] - m[1][1]*m[2][0]) * invDet;
  r[2][1] = -(m[0][0]*m[2][1] - m[0][1]*m[2][0]) * invDet;
  r[2][2] =  (m[0][0]*m[1][1] - m[0][1]*m[1][0]) * invDet;

  return r;
}
