// ============================================================
// PressureGrid.pde
// Renders a deformable mesh surface showing Z-axis force as a
// Gaussian depression — like pressing a finger into a membrane.
// Includes a wireframe reference cage underneath for depth cue.
//
// Public API:
//   initPressureGrid()   — call in setup()
//   drawPressureGrid()   — call in draw() after baseline done
//   handlePGDrag()       — call from mouseDragged()
//
// Reads globals: forceZ (from Decoupling.pde)
// ============================================================

// --- offscreen P3D buffer ---
PGraphics _pgGrid;

static final int PG_GRID_W = 460;
static final int PG_GRID_H = 420;
static final int PG_GRID_X = 870;
static final int PG_GRID_Y = 190;

// --- mesh parameters ---
static final int   GRID_N     = 30;      // NxN vertices
static final float GRID_SIZE  = 280.0;   // world units extent
static final float PG_SIGMA   = 5.5;     // gaussian spread (grid cells)
static final float FZ_SCALE   = 4.0;     // forceZ -> displacement multiplier
static final float PG_FZ_REF  = 50.0;    // Fz at which center reaches full blue (N)

// --- rotation state ---
float _pgRotX = -0.65;
float _pgRotY =  0.45;

// ============================================================
void initPressureGrid() {
  _pgGrid = createGraphics(PG_GRID_W, PG_GRID_H, P3D);
  println("[PressureGrid] Buffer created (" + PG_GRID_W + "x" + PG_GRID_H + ")");
}

// ============================================================
void drawPressureGrid() {
  float cellSize = GRID_SIZE / GRID_N;
  float halfGrid = GRID_SIZE / 2.0;

  // center displacement driven by Fz
  float centerDisp = -forceZ * FZ_SCALE;   // negative Fz = push down

  // --- precompute vertex heights ---
  float[][] hts = new float[GRID_N + 1][GRID_N + 1];
  float refDisp = FZ_SCALE * PG_FZ_REF;   // fixed reference for color mapping
  float cx = GRID_N / 2.0;
  float cz = GRID_N / 2.0;
  float sig2 = 2.0 * PG_SIGMA * PG_SIGMA;

  for (int i = 0; i <= GRID_N; i++) {
    for (int j = 0; j <= GRID_N; j++) {
      float dx = i - cx;
      float dz = j - cz;
      hts[i][j] = centerDisp * exp(-(dx * dx + dz * dz) / sig2);
    }
  }

  // ---- begin offscreen render ----
  _pgGrid.beginDraw();
  _pgGrid.background(30, 30, 40);
  _pgGrid.lights();
  _pgGrid.ambientLight(50, 50, 55);
  _pgGrid.directionalLight(200, 200, 210, -0.4, -1.0, -0.5);

  _pgGrid.translate(PG_GRID_W / 2, PG_GRID_H * 0.42, 0);
  _pgGrid.rotateX(_pgRotX);
  _pgGrid.rotateY(_pgRotY);

  // === 1. Filled color surface (QUAD_STRIP per row) ===
  for (int i = 0; i < GRID_N; i++) {
    _pgGrid.beginShape(QUAD_STRIP);
    _pgGrid.noStroke();
    for (int j = 0; j <= GRID_N; j++) {
      for (int di = 0; di <= 1; di++) {
        float wx = (i + di) * cellSize - halfGrid;
        float wz = j * cellSize - halfGrid;
        float wy = hts[i + di][j];
        _pgGrid.fill(pgHeightColor(wy, refDisp));
        _pgGrid.vertex(wx, wy, wz);
      }
    }
    _pgGrid.endShape();
  }

  // === 2. Surface wireframe (every 5 cells for clarity) ===
  int wireStep = 5;
  _pgGrid.noFill();
  _pgGrid.stroke(0, 0, 0, 55);
  _pgGrid.strokeWeight(0.6);

  // grid lines along Z
  for (int i = 0; i <= GRID_N; i += wireStep) {
    for (int j = 0; j < GRID_N; j++) {
      float x0 = i * cellSize - halfGrid;
      float z0 = j * cellSize - halfGrid;
      float z1 = (j + 1) * cellSize - halfGrid;
      _pgGrid.line(x0, hts[i][j], z0, x0, hts[i][j + 1], z1);
    }
  }
  // grid lines along X
  for (int j = 0; j <= GRID_N; j += wireStep) {
    for (int i = 0; i < GRID_N; i++) {
      float x0 = i * cellSize - halfGrid;
      float x1 = (i + 1) * cellSize - halfGrid;
      float z0 = j * cellSize - halfGrid;
      _pgGrid.line(x0, hts[i][j], z0, x1, hts[i + 1][j], z0);
    }
  }

  // === 3. Reference cage underneath ===
  float cageBottom = max(abs(centerDisp) * 1.3, 18);
  _pgGrid.stroke(100, 100, 120, 70);
  _pgGrid.strokeWeight(0.5);
  _pgGrid.noFill();

  // four vertical corner pillars
  _pgGrid.line(-halfGrid, 0, -halfGrid, -halfGrid, cageBottom, -halfGrid);
  _pgGrid.line( halfGrid, 0, -halfGrid,  halfGrid, cageBottom, -halfGrid);
  _pgGrid.line( halfGrid, 0,  halfGrid,  halfGrid, cageBottom,  halfGrid);
  _pgGrid.line(-halfGrid, 0,  halfGrid, -halfGrid, cageBottom,  halfGrid);

  // bottom rectangle outline
  _pgGrid.beginShape();
  _pgGrid.vertex(-halfGrid, cageBottom, -halfGrid);
  _pgGrid.vertex( halfGrid, cageBottom, -halfGrid);
  _pgGrid.vertex( halfGrid, cageBottom,  halfGrid);
  _pgGrid.vertex(-halfGrid, cageBottom,  halfGrid);
  _pgGrid.endShape(CLOSE);

  // bottom grid lines (sparse)
  for (int i = 0; i <= GRID_N; i += wireStep) {
    float x = i * cellSize - halfGrid;
    _pgGrid.line(x, cageBottom, -halfGrid, x, cageBottom, halfGrid);
  }
  for (int j = 0; j <= GRID_N; j += wireStep) {
    float z = j * cellSize - halfGrid;
    _pgGrid.line(-halfGrid, cageBottom, z, halfGrid, cageBottom, z);
  }

  _pgGrid.endDraw();

  // ---- blit to main canvas ----
  image(_pgGrid, PG_GRID_X, PG_GRID_Y);

  // label below
  fill(100);
  textSize(10);
  textAlign(CENTER, TOP);
  text("Z-axis Pressure   Fz = " + nf(forceZ, 1, 3) + " N   |   Drag to rotate",
       PG_GRID_X + PG_GRID_W / 2, PG_GRID_Y + PG_GRID_H + 2);
  textAlign(LEFT, BASELINE);
  textSize(14);
}

// ============================================================
// Color mapping: absolute vertex displacement against fixed ref.
//   t = |displacement| / (FZ_SCALE * PG_FZ_REF)
//   t=0  -> red   H=0    (no force / edge)
//   t=0.5 -> green H=120  (moderate force)
//   t=1  -> blue  H=240  (full-scale force)
// Small Fz → everything stays red. Large Fz → center turns blue.
// ============================================================
color pgHeightColor(float h, float refD) {
  float t = constrain(abs(h) / refD, 0, 1);

  pushStyle();
  colorMode(HSB, 360, 100, 100);
  float hue = t * 240;        // 0(red) -> 120(green) -> 240(blue)
  float sat = 70 + t * 25;    // 70% -> 95%
  float bri = 80 + t * 10;    // 80% -> 90%
  color c = color(hue, sat, bri);
  popStyle();
  return c;
}

// ============================================================
// Mouse drag — rotate pressure grid view
// ============================================================
void handlePGDrag() {
  if (mouseX >= PG_GRID_X && mouseX <= PG_GRID_X + PG_GRID_W &&
      mouseY >= PG_GRID_Y && mouseY <= PG_GRID_Y + PG_GRID_H) {
    float dx = mouseX - pmouseX;
    float dy = mouseY - pmouseY;
    _pgRotY += dx * 0.01;
    _pgRotX += dy * 0.01;
    _pgRotX = constrain(_pgRotX, -HALF_PI + 0.1, HALF_PI - 0.1);
  }
}
