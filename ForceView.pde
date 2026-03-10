// ============================================================
// ForceView.pde
// Two-panel visualization of decoupled force vectors:
//   Left  — 3D coordinate system with per-axis arrows + resultant
//   Right — Vertical bar chart (Fx, Fy, Fz, |F|)
//
// Public API:
//   initForceView()    — call in setup()
//   drawForceView()    — call in draw() after baseline done
//   handleFVDrag()     — call from mouseDragged()
//
// Reads globals: forceX, forceY, forceZ (from Decoupling.pde)
// ============================================================

// --- 3D offscreen buffer ---
PGraphics _pg3d;

static final int PG_W = 400;
static final int PG_H = 380;

// --- layout positions ---
static final int FV_3D_X  = 30;
static final int FV_3D_Y  = 200;
static final int FV_BAR_X = 460;
static final int FV_BAR_Y = 200;
static final int FV_BAR_W = 390;
static final int FV_BAR_H = 380;

// --- rotation state ---
float _fvRotX = -0.4;   // initial tilt (radians)
float _fvRotY =  0.6;   // initial pan

// --- axis colors (reuse project palette) ---
color FV_COL_X = 0xFF508CFF;   // (80, 140, 255)
color FV_COL_Y = 0xFF64DC64;   // (100, 220, 100)
color FV_COL_Z = 0xFFFFA03C;   // (255, 160, 60)
color FV_COL_R = 0xFFFFFFC8;   // (255, 255, 200) resultant

// ============================================================
void initForceView() {
  _pg3d = createGraphics(PG_W, PG_H, P3D);
  println("[ForceView] 3D buffer created (" + PG_W + "x" + PG_H + ")");
}

// ============================================================
void drawForceView() {
  draw3DPanel();
  drawBarChart();
}

// ============================================================
// 3D panel — axes + force arrows + resultant
// ============================================================
void draw3DPanel() {
  float axisLen = 120;   // half-axis length in 3D units

  // --- auto-scale: map max force to ~100 px arrow ---
  float maxF = max(max(abs(forceX), abs(forceY)), max(abs(forceZ), 0.001));
  float scale = 100.0 / maxF;

  _pg3d.beginDraw();
  _pg3d.background(25, 25, 35);
  _pg3d.lights();

  // center camera
  _pg3d.translate(PG_W / 2, PG_H / 2, 0);
  _pg3d.rotateX(_fvRotX);
  _pg3d.rotateY(_fvRotY);

  // --- draw grid-like axis lines (thin, gray) ---
  _pg3d.strokeWeight(1);
  _pg3d.stroke(80);
  // X axis
  _pg3d.line(-axisLen, 0, 0, axisLen, 0, 0);
  // Y axis (Processing Y is inverted; we keep convention: up = +Y displayed)
  _pg3d.line(0, axisLen, 0, 0, -axisLen, 0);
  // Z axis
  _pg3d.line(0, 0, -axisLen, 0, 0, axisLen);

  // --- axis labels ---
  _pg3d.textSize(12);
  _pg3d.fill(FV_COL_X);
  _pg3d.text("+X", axisLen + 6, 4, 0);
  _pg3d.fill(FV_COL_Y);
  _pg3d.text("+Y", 4, -axisLen - 6, 0);
  _pg3d.fill(FV_COL_Z);
  _pg3d.text("+Z", 4, 4, axisLen + 6);

  // --- force arrows on each axis ---
  // X arrow (along X axis)
  float arrowX = forceX * scale;
  drawArrow3D(_pg3d, 0, 0, 0, arrowX, 0, 0, FV_COL_X, 2.5);

  // Y arrow (up = positive, so negate for Processing coords)
  float arrowY = forceY * scale;
  drawArrow3D(_pg3d, 0, 0, 0, 0, -arrowY, 0, FV_COL_Y, 2.5);

  // Z arrow (into screen = positive Z)
  float arrowZ = forceZ * scale;
  drawArrow3D(_pg3d, 0, 0, 0, 0, 0, arrowZ, FV_COL_Z, 2.5);

  // --- resultant vector ---
  drawArrow3D(_pg3d, 0, 0, 0, arrowX, -arrowY, arrowZ, FV_COL_R, 3.0);

  _pg3d.endDraw();

  // blit to main canvas
  image(_pg3d, FV_3D_X, FV_3D_Y);

  // panel label (2D, on main canvas)
  fill(100);
  textSize(10);
  textAlign(CENTER, TOP);
  text("Drag to rotate", FV_3D_X + PG_W / 2, FV_3D_Y + PG_H + 2);
  textAlign(LEFT, BASELINE);
  textSize(14);
}

// ============================================================
// drawArrow3D — line + cone-style arrowhead
// ============================================================
void drawArrow3D(PGraphics pg, float x1, float y1, float z1,
                                float x2, float y2, float z2,
                                color c, float sw) {
  float dx = x2 - x1;
  float dy = y2 - y1;
  float dz = z2 - z1;
  float len = sqrt(dx*dx + dy*dy + dz*dz);
  if (len < 0.5) return;   // too small to draw

  pg.stroke(c);
  pg.strokeWeight(sw);
  pg.line(x1, y1, z1, x2, y2, z2);

  // arrowhead: small lines fanning from tip
  float headLen = min(len * 0.25, 12);
  float nx = dx / len;
  float ny = dy / len;
  float nz = dz / len;

  // find two perpendicular vectors (cross product with arbitrary up)
  float ux, uy, uz;
  if (abs(ny) < 0.9) {
    // cross(n, (0,1,0))
    ux = nz;  uy = 0;  uz = -nx;
  } else {
    // cross(n, (1,0,0))
    ux = 0;  uy = -nz;  uz = ny;
  }
  float uLen = sqrt(ux*ux + uy*uy + uz*uz);
  if (uLen < 1e-6) return;
  ux /= uLen;  uy /= uLen;  uz /= uLen;

  // second perpendicular: cross(n, u)
  float vx = ny*uz - nz*uy;
  float vy = nz*ux - nx*uz;
  float vz = nx*uy - ny*ux;

  float headR = headLen * 0.4;
  pg.strokeWeight(sw * 0.8);

  // 4 arrowhead prongs
  for (int i = 0; i < 4; i++) {
    float angle = i * HALF_PI;
    float px = ux * cos(angle) + vx * sin(angle);
    float py = uy * cos(angle) + vy * sin(angle);
    float pz = uz * cos(angle) + vz * sin(angle);

    float bx = x2 - nx * headLen + px * headR;
    float by = y2 - ny * headLen + py * headR;
    float bz = z2 - nz * headLen + pz * headR;
    pg.line(x2, y2, z2, bx, by, bz);
  }
}

// ============================================================
// Bar chart — Fx, Fy, Fz, |F|
// ============================================================
void drawBarChart() {
  int cx = FV_BAR_X;
  int cy = FV_BAR_Y;
  int cw = FV_BAR_W;
  int ch = FV_BAR_H;

  // panel background
  fill(25, 25, 35);
  noStroke();
  rect(cx, cy, cw, ch, 6);

  float fMag = sqrt(forceX*forceX + forceY*forceY + forceZ*forceZ);
  float[] vals   = { forceX, forceY, forceZ, fMag };
  String[] names = { "Fx", "Fy", "Fz", "|F|" };
  color[] cols   = { FV_COL_X, FV_COL_Y, FV_COL_Z, FV_COL_R };

  // auto-scale
  float maxVal = 0.001;
  for (float v : vals) maxVal = max(maxVal, abs(v));

  int barCount = 4;
  int barW     = 50;
  int gap      = (cw - barCount * barW) / (barCount + 1);
  int zeroY    = cy + ch / 2;       // center line = zero force
  int halfH    = (ch / 2) - 40;     // max bar extent (leave room for labels)

  // zero line
  stroke(70);
  strokeWeight(1);
  line(cx + 10, zeroY, cx + cw - 10, zeroY);
  noStroke();

  for (int i = 0; i < barCount; i++) {
    int bx = cx + gap + i * (barW + gap);
    float val = vals[i];
    float barH = (val / maxVal) * halfH;

    // bar body
    fill(cols[i]);
    if (i < 3) {
      // Fx/Fy/Fz: bidirectional (positive up, negative down)
      if (barH >= 0) {
        rect(bx, zeroY - barH, barW, barH, 3, 3, 0, 0);
      } else {
        rect(bx, zeroY, barW, -barH, 0, 0, 3, 3);
      }
    } else {
      // |F|: always positive (upward)
      float magH = (fMag / maxVal) * halfH;
      rect(bx, zeroY - magH, barW, magH, 3, 3, 0, 0);
    }

    // value label
    fill(220);
    textSize(11);
    textAlign(CENTER, BOTTOM);
    float labelY;
    if (i < 3) {
      labelY = (barH >= 0) ? zeroY - barH - 4 : zeroY - barH + 14;
      // if bar goes down, label above zero
      if (barH < 0) {
        textAlign(CENTER, TOP);
        labelY = zeroY + (-barH) + 4;
      } else {
        labelY = zeroY - barH - 4;
      }
    } else {
      float magH = (fMag / maxVal) * halfH;
      labelY = zeroY - magH - 4;
    }
    text(nf(val, 1, 4), bx + barW / 2, labelY);

    // axis name below chart
    fill(cols[i]);
    textSize(13);
    textAlign(CENTER, TOP);
    text(names[i], bx + barW / 2, cy + ch - 22);
  }

  // unit label
  fill(90);
  textSize(10);
  textAlign(CENTER, TOP);
  text("Force (N)", cx + cw / 2, cy + ch - 6);

  // reset
  textAlign(LEFT, BASELINE);
  textSize(14);
  noStroke();
}

// ============================================================
// Mouse drag handler — rotate 3D view
// Call from mouseDragged() in TDF_Visual
// ============================================================
void handleFVDrag() {
  // only rotate if mouse is within the 3D panel area
  if (mouseX >= FV_3D_X && mouseX <= FV_3D_X + PG_W &&
      mouseY >= FV_3D_Y && mouseY <= FV_3D_Y + PG_H) {
    float dx = mouseX - pmouseX;
    float dy = mouseY - pmouseY;
    _fvRotY += dx * 0.01;
    _fvRotX += dy * 0.01;
    // clamp vertical rotation to avoid flipping
    _fvRotX = constrain(_fvRotX, -HALF_PI + 0.1, HALF_PI - 0.1);
  }
}
