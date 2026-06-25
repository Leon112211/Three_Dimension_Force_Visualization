// ============================================================
// ForceView.pde
// Two-panel visualization of decoupled force vectors:
//   Left  — 3D force instrument: cage + colored axes + arrows + resultant
//   Right — Vertical bar chart (Fx, Fy, Fz, |F|)
//
// Public API:
//   initForceView()    — call in setup()
//   drawForceView()    — call in draw() after baseline done
//   handleFVDrag()     — call from mouseDragged()
//   Display scale comes from the global Axis Ranges panel (rangeX/Y/Z).
//
// Reads globals: forceX, forceY, forceZ (from Decoupling.pde)
//
// Axis remap (kept): screen down=+Z (forceZ), lower-left=+X (forceX),
// lower-right=+Y (forceY).  Model dirs: +X->-x, +Y->+z, +Z->+y.
// ============================================================

import processing.opengl.*;   // PGL — depth-buffer clear that keeps the resultant on top

// --- 3D offscreen buffer ---
PGraphics _pg3d;
PImage _fvVignette;      // cached corner-darkening overlay (depth-safe, drawn on main canvas)

static final int PG_W = 400;
static final int PG_H = 400;

// --- layout positions ---
static final int FV_3D_X  = 30;
static final int FV_3D_Y  = 210;
static final int FV_BAR_X = 450;
static final int FV_BAR_Y = 210;
static final int FV_BAR_W = 400;
static final int FV_BAR_H = 400;

// --- rotation state ---
float _fvRotX = -0.4;   // initial tilt (radians)
float _fvRotY =  0.6;   // initial pan
int   _fvLastInteract = 0;   // frameCount of last drag/slider touch (idle auto-rotate)

// --- axis colors (reuse project palette) ---
color FV_COL_X = 0xFF5A92FF;
color FV_COL_Y = 0xFF66E07D;
color FV_COL_Z = 0xFFFFA23D;
color FV_COL_R = 0xFFFFF5B8;

static final float FV_AXIS_LEN = 120;   // half-axis length in 3D units
static final int   FV_SS = 1;           // 3D buffer supersample (1 = fast; 2 = sharper but ~4x the fill cost)

// ============================================================
void initForceView() {
  _pg3d = createGraphics(PG_W * FV_SS, PG_H * FV_SS, P3D);
  _pg3d.beginDraw();
  _pg3d.sphereDetail(18);   // set once; avoids per-frame cost
  _pg3d.endDraw();
  _fvVignette = makeFVVignette(PG_W, PG_H);
  println("[ForceView] 3D buffer created (" + (PG_W * FV_SS) + "x" + (PG_H * FV_SS) + ", " + FV_SS + "x SS)");
}

// ============================================================
void drawForceView() {
  draw3DPanel();
  drawBarChart();
}

// ============================================================
// 3D panel — cage + colored axes + force arrows + resultant
// ============================================================
void draw3DPanel() {
  float axisLen = FV_AXIS_LEN;

  // idle auto-rotation (yaw only) when the user hasn't interacted recently
  if (frameCount - _fvLastInteract > 90) _fvRotY += 0.002;

  // --- per-axis perceptual length (drawn pixels only; readouts stay raw N) ---
  float fMag = sqrt(forceX*forceX + forceY*forceY + forceZ*forceZ);
  float arrowX = fvAxisPx(forceX, rangeX, axisLen);   // each axis scaled by its own range
  float arrowY = fvAxisPx(forceY, rangeY, axisLen);
  float arrowZ = fvAxisPx(forceZ, rangeZ, axisLen);

  // resultant tip in model space (remapped): +X->-x, +Y->+z, +Z->+y
  float rX = -arrowX, rY = arrowZ, rZ = arrowY;
  float rLen = sqrt(rX*rX + rY*rY + rZ*rZ);           // clamp into the axis sphere
  if (rLen > axisLen) { float s = axisLen / rLen; rX *= s; rY *= s; rZ *= s; }

  _pg3d.beginDraw();
  _pg3d.background(UI_PANEL);
  if (UI_FONT != null) _pg3d.textFont(UI_FONT);
  _pg3d.lights();
  _pg3d.ambientLight(55, 60, 70);
  _pg3d.directionalLight(190, 210, 230, -0.5, -0.8, -0.4);
  _pg3d.directionalLight(60, 70, 90, 0.6, 0.4, 0.5);   // dim rim light for shape

  _pg3d.scale(FV_SS);                  // supersample: draw in logical PG_W coords at SSx resolution
  _pg3d.translate(PG_W / 2, PG_H / 2, 0);
  _pg3d.rotateX(_fvRotX);
  _pg3d.rotateY(_fvRotY);

  // --- structure behind the data ---
  drawFVCage(axisLen);
  drawFVGroundGrid(axisLen);
  drawFVAxes(axisLen);

  // origin hub
  _pg3d.noStroke();
  _pg3d.fill(UI_TEXT);
  _pg3d.sphere(2.6);

  // --- component arrows (solid cones), mapped to model dirs ---
  drawArrow3D(_pg3d, 0, 0, 0, -arrowX, 0, 0, FV_COL_X, 3.0);   // +X -> model -x
  drawArrow3D(_pg3d, 0, 0, 0, 0, 0, arrowY, FV_COL_Y, 3.0);    // +Y -> model +z
  drawArrow3D(_pg3d, 0, 0, 0, 0, arrowZ, 0, FV_COL_Z, 3.0);    // +Z -> model +y

  // --- component drop-lines (staircase origin->x->z->y tip) ---
  drawFVDropLines(rX, rY, rZ, axisLen);

  // --- resultant (hero) with glow + material ---
  drawFVResultant(rX, rY, rZ);

  // capture screen positions of the positive axis tips BEFORE endDraw (buffer px -> design px)
  float sxX = _pg3d.screenX(-axisLen, 0, 0) / FV_SS, syX = _pg3d.screenY(-axisLen, 0, 0) / FV_SS;
  float sxY = _pg3d.screenX(0, 0, axisLen) / FV_SS,  syY = _pg3d.screenY(0, 0, axisLen) / FV_SS;
  float sxZ = _pg3d.screenX(0, axisLen, 0) / FV_SS,  syZ = _pg3d.screenY(0, axisLen, 0) / FV_SS;

  _pg3d.endDraw();

  // --- blit (downscale the SSx buffer for AA) + corner vignette + frame ---
  image(_pg3d, FV_3D_X, FV_3D_Y, PG_W, PG_H);
  image(_fvVignette, FV_3D_X, FV_3D_Y);
  drawPanelFrame(FV_3D_X, FV_3D_Y, PG_W, PG_H, "3D Force Vector");

  // truthful numeric readout (raw N)
  drawFVReadout(fMag);

  // crisp, upright, constant-size axis labels on top
  drawFVLabel("+X", sxX, syX, FV_COL_X);
  drawFVLabel("+Y", sxY, syY, FV_COL_Y);
  drawFVLabel("+Z", sxZ, syZ, FV_COL_Z);

  textAlign(LEFT, BASELINE);
  useUIFont(14);
}

// signed perceptual pixel length for one axis component (range = full-scale N)
float fvAxisPx(float f, float range, float axisLen) {
  float tt = constrain(abs(f) / range, 0, 1);
  return (f < 0 ? -1 : 1) * sqrt(tt) * axisLen;
}

// ============================================================
// drawArrow3D — thick shaft + SOLID cone head (lit)
// ============================================================
void drawArrow3D(PGraphics pg, float x1, float y1, float z1,
                                float x2, float y2, float z2,
                                color c, float sw) {
  float dx = x2 - x1, dy = y2 - y1, dz = z2 - z1;
  float len = sqrt(dx*dx + dy*dy + dz*dz);
  if (len < 0.5) return;   // too small to draw

  float nx = dx / len, ny = dy / len, nz = dz / len;
  float headLen = min(len * 0.28, 16);
  float headR   = headLen * 0.42;

  // shaft stops where the cone base begins
  float bx = x2 - nx * headLen, by = y2 - ny * headLen, bz = z2 - nz * headLen;
  pg.stroke(c);
  pg.strokeWeight(sw);
  pg.line(x1, y1, z1, bx, by, bz);

  // orthonormal basis perpendicular to the arrow direction
  float ux, uy, uz;
  if (abs(ny) < 0.9) { ux = nz;  uy = 0;  uz = -nx; }
  else               { ux = 0;   uy = -nz; uz = ny; }
  float ul = sqrt(ux*ux + uy*uy + uz*uz);
  if (ul < 1e-6) return;
  ux /= ul;  uy /= ul;  uz /= ul;
  float vx = ny*uz - nz*uy, vy = nz*ux - nx*uz, vz = nx*uy - ny*ux;

  // solid cone: side triangles + base cap
  int seg = 14;
  pg.noStroke();
  pg.fill(c);
  pg.beginShape(TRIANGLES);
  for (int i = 0; i < seg; i++) {
    float a0 = TWO_PI * i / seg, a1 = TWO_PI * (i + 1) / seg;
    float p0x = ux*cos(a0) + vx*sin(a0), p0y = uy*cos(a0) + vy*sin(a0), p0z = uz*cos(a0) + vz*sin(a0);
    float p1x = ux*cos(a1) + vx*sin(a1), p1y = uy*cos(a1) + vy*sin(a1), p1z = uz*cos(a1) + vz*sin(a1);
    // side
    pg.vertex(x2, y2, z2);
    pg.vertex(bx + p0x*headR, by + p0y*headR, bz + p0z*headR);
    pg.vertex(bx + p1x*headR, by + p1y*headR, bz + p1z*headR);
    // base cap (reversed winding)
    pg.vertex(bx, by, bz);
    pg.vertex(bx + p1x*headR, by + p1y*headR, bz + p1z*headR);
    pg.vertex(bx + p0x*headR, by + p0y*headR, bz + p0z*headR);
  }
  pg.endShape();
}

// ============================================================
// Resultant: lit solid hero, drawn ON TOP of the component arrows
// ============================================================
void drawFVResultant(float rX, float rY, float rZ) {
  float m = sqrt(rX*rX + rY*rY + rZ*rZ);
  if (m < 0.5) return;

  // The resultant often nearly coincides with a dominant axis arrow (e.g. when Fz
  // dominates). Two solid arrows at the same depth depth-fight -> the flicker.
  // Clear the depth buffer so the resultant draws on top of the component arrows
  // and only depth-sorts against itself (its cone still self-occludes correctly).
  PGL pgl = _pg3d.beginPGL();
  pgl.clear(PGL.DEPTH_BUFFER_BIT);
  _pg3d.endPGL();

  // lit solid hero (emissive gives a self-lit pale glow without overlapping geometry)
  _pg3d.specular(255);
  _pg3d.shininess(28);
  _pg3d.emissive(red(FV_COL_R) * 0.2, green(FV_COL_R) * 0.2, blue(FV_COL_R) * 0.2);
  drawArrow3D(_pg3d, 0, 0, 0, rX, rY, rZ, FV_COL_R, 3.5);
  _pg3d.emissive(0, 0, 0);
  _pg3d.specular(0, 0, 0);
  _pg3d.shininess(1);
}

// ============================================================
// Structure helpers (cage, ground grid, colored axes, drop-lines)
// ============================================================
color fvDim(color c) { return color(red(c), green(c), blue(c), 70); }

void drawFVCage(float L) {
  _pg3d.noFill();
  _pg3d.stroke(red(UI_GRID), green(UI_GRID), blue(UI_GRID), 90);
  _pg3d.strokeWeight(1);
  _pg3d.box(2 * L);
}

void drawFVGroundGrid(float L) {
  _pg3d.stroke(red(UI_GRID), green(UI_GRID), blue(UI_GRID), 55);
  _pg3d.strokeWeight(1);
  int n = 6;
  float y = L;   // floor sits on the +y (down) face of the cage
  for (int i = 0; i <= n; i++) {
    float c = -L + (2 * L) * i / n;
    _pg3d.line(c, y, -L, c, y, L);
    _pg3d.line(-L, y, c, L, y, c);
  }
}

void drawFVAxes(float L) {
  // positive halves: bright, in axis color
  _pg3d.strokeWeight(1.6);
  _pg3d.stroke(FV_COL_X);  _pg3d.line(0, 0, 0, -L, 0, 0);   // +X -> model -x
  _pg3d.stroke(FV_COL_Y);  _pg3d.line(0, 0, 0, 0, 0, L);    // +Y -> model +z
  _pg3d.stroke(FV_COL_Z);  _pg3d.line(0, 0, 0, 0, L, 0);    // +Z -> model +y
  // negative halves: dim, dashed
  _pg3d.strokeWeight(1.0);
  dashLine3D(_pg3d, 0, 0, 0, L, 0, 0,  fvDim(FV_COL_X), 5, 5);
  dashLine3D(_pg3d, 0, 0, 0, 0, 0, -L, fvDim(FV_COL_Y), 5, 5);
  dashLine3D(_pg3d, 0, 0, 0, 0, -L, 0, fvDim(FV_COL_Z), 5, 5);
}

// Staircase origin -> x -> z -> y(tip): each leg is one component, axis-colored.
void drawFVDropLines(float rX, float rY, float rZ, float L) {
  if (rX*rX + rY*rY + rZ*rZ < 4) return;
  _pg3d.strokeWeight(1.2);
  dashLine3D(_pg3d, 0,  0,  0,  rX, 0,  0,  fvDim(FV_COL_X), 4, 4);   // Fx (model x)
  dashLine3D(_pg3d, rX, 0,  0,  rX, 0,  rZ, fvDim(FV_COL_Y), 4, 4);   // Fy (model z)
  dashLine3D(_pg3d, rX, 0,  rZ, rX, rY, rZ, fvDim(FV_COL_Z), 4, 4);   // Fz (model y)
  // faint vertical shadow line to the floor for grounding
  dashLine3D(_pg3d, rX, rY, rZ, rX, L, rZ,
             color(85, 93, 110, 60), 3, 5);
}

void dashLine3D(PGraphics pg, float ax, float ay, float az,
                              float bx, float by, float bz,
                              color col, float dash, float gap) {
  float dx = bx - ax, dy = by - ay, dz = bz - az;
  float L = sqrt(dx*dx + dy*dy + dz*dz);
  if (L < 0.5) return;
  float ux = dx / L, uy = dy / L, uz = dz / L, step = dash + gap;
  pg.stroke(col);
  for (float s = 0; s < L; s += step) {
    float e = min(s + dash, L);
    pg.line(ax + ux*s, ay + uy*s, az + uz*s, ax + ux*e, ay + uy*e, az + uz*e);
  }
}

// ============================================================
// Main-canvas overlays (labels, readout, scale slider, vignette)
// ============================================================
void drawFVLabel(String s, float sx, float sy, color c) {
  if (sx < 0 || sx > PG_W || sy < 0 || sy > PG_H) return;   // tip off-buffer / behind camera
  useUIFont(12);
  textAlign(CENTER, CENTER);
  fill(0, 0, 0, 150);
  text(s, FV_3D_X + sx + 1, FV_3D_Y + sy + 1);
  fill(c);
  text(s, FV_3D_X + sx, FV_3D_Y + sy);
  textAlign(LEFT, BASELINE);
}

// signed value, padded so positives align with negatives (digits/decimals line up)
String fvFmt(float v) {
  String s = nf(v, 1, 3);
  return (s.charAt(0) == '-') ? s : " " + s;
}

void drawFVReadout(float fMag) {
  float x0 = FV_3D_X + 10;
  float y0 = FV_3D_Y + PG_H - 92;

  useMonoFont(11);
  textAlign(LEFT, TOP);
  float lx = x0 + 8;                  // label column
  float vx = lx + textWidth("|F| ");  // value column — all numbers align past the widest label
  fill(FV_COL_X);  text("Fx",  lx, y0 + 10);  text(fvFmt(forceX),      vx, y0 + 10);
  fill(FV_COL_Y);  text("Fy",  lx, y0 + 26);  text(fvFmt(forceY),      vx, y0 + 26);
  fill(FV_COL_Z);  text("Fz",  lx, y0 + 42);  text(fvFmt(forceZ),      vx, y0 + 42);
  fill(UI_RESULT); text("|F|", lx, y0 + 58);  text(fvFmt(fMag) + " N", vx, y0 + 58);
  textAlign(LEFT, BASELINE);
}

PImage makeFVVignette(int w, int h) {
  PImage img = createImage(w, h, ARGB);
  img.loadPixels();
  float cx = w / 2.0, cy = h / 2.0, maxR = sqrt(cx*cx + cy*cy);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float d = constrain(dist(x, y, cx, cy) / maxR, 0, 1);
      float a = pow(d, 2.2) * 150;   // transparent center -> dark corners
      img.pixels[y * w + x] = color(8, 10, 16, a);
    }
  }
  img.updatePixels();
  return img;
}

// ============================================================
// Bar chart — Fx, Fy, Fz, |F|
// ============================================================
void drawBarChart() {
  int cx = FV_BAR_X;
  int cy = FV_BAR_Y;
  int cw = FV_BAR_W;
  int ch = FV_BAR_H;

  drawPanelBase(cx, cy, cw, ch, "Force Components");

  float fMag = sqrt(forceX*forceX + forceY*forceY + forceZ*forceZ);
  float[] vals   = { forceX, forceY, forceZ, fMag };
  String[] names = { "Fx", "Fy", "Fz", "|F|" };
  color[] cols   = { FV_COL_X, FV_COL_Y, FV_COL_Z, FV_COL_R };

  // per-axis full-scale from the global ranges; |F| uses the combined range
  float magRange = sqrt(rangeX*rangeX + rangeY*rangeY + rangeZ*rangeZ);
  float[] maxVals = { rangeX, rangeY, rangeZ, magRange };

  int barCount = 4;
  int barW     = 50;
  int gap      = (cw - barCount * barW) / (barCount + 1);
  int zeroY    = cy + ch / 2;       // center line = zero force
  int halfH    = (ch / 2) - 40;     // max bar extent (leave room for labels)

  // zero line
  stroke(UI_GRID);
  strokeWeight(1);
  line(cx + 10, zeroY, cx + cw - 10, zeroY);
  stroke(UI_GRID, 120);
  for (int gy = cy + 54; gy < cy + ch - 44; gy += 42) {
    line(cx + 16, gy, cx + cw - 16, gy);
  }
  noStroke();

  for (int i = 0; i < barCount; i++) {
    int bx = cx + gap + i * (barW + gap);
    float val = vals[i];
    float maxVal = maxVals[i];
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
    fill(UI_TEXT);
    useMonoFont(11);
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
    useUIFont(13);
    textAlign(CENTER, TOP);
    text(names[i], bx + barW / 2, cy + ch - 22);
  }

  // reset
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

// ============================================================
// Mouse drag handler — rotate 3D view
// Call from mouseDragged() in TDF_Visual
// ============================================================
void handleFVDrag() {
  float mx = uiMouseX();
  float my = uiMouseY();
  float pmx = uiPMouseX();
  float pmy = uiPMouseY();

  // only rotate if mouse is within the 3D panel area
  if (mx >= FV_3D_X && mx <= FV_3D_X + PG_W &&
      my >= FV_3D_Y && my <= FV_3D_Y + PG_H) {
    float dx = mx - pmx;
    float dy = my - pmy;
    _fvRotY += dx * 0.01;
    _fvRotX += dy * 0.01;
    // clamp vertical rotation to avoid flipping
    _fvRotX = constrain(_fvRotX, -HALF_PI + 0.1, HALF_PI - 0.1);
    _fvLastInteract = frameCount;
  }
}
