// ============================================================
// TangentialCompass.pde
// Circular compass gauge showing XY tangential force as a single
// rotating arrow. The arrow direction = atan2(Fy, Fx), its length
// and width scale with |Fxy|. Color shifts cool→warm with magnitude.
//
// Public API:
//   initCompass()                — call in setup()
//   drawCompass(float fx, float fy) — call in draw()
//
// ============================================================

// --- layout ---
static final int TC_X = 30;
static final int TC_Y = 630;
static final int TC_W = 400;         // panel width  (col A)
static final int TC_SIZE = 280;      // panel height (row 3)
static final float TC_R = 105.0;     // gauge circle radius (px)
static final float TC_FXY_REF = 5.0; // Fxy at which arrow reaches full length (N)

// --- needle damping state (smooths twitch only; raw values still used for readouts) ---
float _tcFxySm = 0;                           // EMA-smoothed |Fxy|
float _tcThetaSm = 0;                         // smoothed needle angle (shortest-path lerp)
static final float TC_EMA_ALPHA = 0.2;        // magnitude smoothing (higher = less damping)
static final float TC_ANG_ALPHA = 0.3;        // angle smoothing (higher = less damping)

void initCompass() {
  println("[TangentialCompass] Initialized");
}

// ============================================================
void drawCompass(float fx, float fy) {
  float cx = TC_X + TC_W / 2.0;
  float cy = TC_Y + TC_SIZE / 2.0;

  drawPanelBase(TC_X, TC_Y, TC_W, TC_SIZE, "XY Tangential Force");

  // --- outer ring ---
  noFill();
  stroke(76, 88, 112);
  strokeWeight(2);
  ellipse(cx, cy, TC_R * 2, TC_R * 2);

  // --- crosshair reference lines ---
  stroke(UI_GRID);
  strokeWeight(0.6);
  line(cx - TC_R, cy, cx + TC_R, cy);   // horizontal
  line(cx, cy - TC_R, cx, cy + TC_R);   // vertical

  // --- tick marks around circle (every 30 deg) ---
  stroke(82, 93, 116);
  strokeWeight(1.0);
  for (int deg = 0; deg < 360; deg += 30) {
    float rad = radians(deg);
    float cosr = cos(rad);
    float sinr = sin(rad);
    float r0 = (deg % 90 == 0) ? TC_R - 10 : TC_R - 6;
    line(cx + cosr * r0, cy - sinr * r0,
         cx + cosr * TC_R, cy - sinr * TC_R);
  }

  // --- axis labels ---
  textSize(11);
  textAlign(CENTER, CENTER);
  fill(UI_X);   // X color
  text("+X", cx + TC_R + 14, cy);
  text("-X", cx - TC_R - 14, cy);
  fill(UI_Y);  // Y color
  text("+Y", cx, cy - TC_R - 12);
  text("-Y", cx, cy + TC_R + 12);

  // --- raw force vector (used as-is for the text readouts below) ---
  float fxy = sqrt(fx * fx + fy * fy);
  float theta = atan2(fy, fx);   // angle in radians

  // --- damping: smooth magnitude + angle so the needle glides instead of twitching ---
  _tcFxySm += (fxy - _tcFxySm) * TC_EMA_ALPHA;
  if (fxy > 0.001) {
    float dAng = theta - _tcThetaSm;
    while (dAng >  PI) dAng -= TWO_PI;          // shortest-path angle interpolation
    while (dAng < -PI) dAng += TWO_PI;
    _tcThetaSm += dAng * TC_ANG_ALPHA;
  }

  // --- draw center-pivot arrow if force is non-trivial ---
  if (_tcFxySm > 0.001) {
    // normalized magnitude (0..1, clamped) from the smoothed value;
    // full-scale = combined XY range (keeps the needle's true direction)
    float t = constrain(_tcFxySm / rangeXY(), 0, 1);

    // symmetric half-length: both sides equal, max reaches circle edge
    float halfLen  = t * TC_R;
    float frontLen = halfLen;
    float backLen  = halfLen;

    // width scales with force
    float baseW = 4.0 + t * 8.0;

    // color
    color arrowCol = tcForceColor(t);

    // direction vectors from the smoothed angle (screen: +X right, +Y up -> negate sin)
    float dirX =  cos(_tcThetaSm);
    float dirY = -sin(_tcThetaSm);
    float perpX = -dirY;   // perpendicular
    float perpY =  dirX;

    // key points
    float tipX  = cx + dirX * frontLen;
    float tipY  = cy + dirY * frontLen;
    float tailX = cx - dirX * backLen;
    float tailY = cy - dirY * backLen;

    // --- arrow body: filled quad (wider at center, tapering to both ends) ---
    noStroke();
    fill(arrowCol);
    float hw = baseW * 0.45;    // half-width at center
    float tw = baseW * 0.15;    // half-width at tail

    // front body: quad from center-width to pointed tip
    beginShape();
    vertex(cx + perpX * hw,  cy + perpY * hw);
    vertex(cx - perpX * hw,  cy - perpY * hw);
    vertex(tipX - perpX * 1, tipY - perpY * 1);
    vertex(tipX + perpX * 1, tipY + perpY * 1);
    endShape(CLOSE);

    // arrowhead triangle (extends beyond front body)
    float headBase = frontLen * 0.7;
    float hbX = cx + dirX * headBase;
    float hbY = cy + dirY * headBase;
    float headW = baseW * 0.7;
    triangle(tipX, tipY,
             hbX + perpX * headW, hbY + perpY * headW,
             hbX - perpX * headW, hbY - perpY * headW);

    // tail body: quad from center-width to narrow tail
    beginShape();
    vertex(cx + perpX * hw,  cy + perpY * hw);
    vertex(cx - perpX * hw,  cy - perpY * hw);
    vertex(tailX - perpX * tw, tailY - perpY * tw);
    vertex(tailX + perpX * tw, tailY + perpY * tw);
    endShape(CLOSE);
  }

  // --- center dot ---
  noStroke();
  fill(UI_TEXT);
  ellipse(cx, cy, 6, 6);

  // --- text readouts ---
  textAlign(LEFT, BASELINE);
  useMonoFont(10);

  // magnitude
  fill(UI_TEXT);
  text("|Fxy| = " + nf(fxy, 1, 3) + " N", TC_X + 6, TC_Y + TC_SIZE - 20);

  // angle (degrees)
  float angleDeg = degrees(theta);
  if (angleDeg < 0) angleDeg += 360;
  text("Angle = " + nf(angleDeg, 1, 1) + " deg", TC_X + 6, TC_Y + TC_SIZE - 6);

  // reset state
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

// ============================================================
// Color mapping: t=0 (no force) → cyan,  t=1 (max force) → red
// Passes through yellow/orange in the middle for warm intensity feel.
// ============================================================
color tcForceColor(float t) {
  // HSB: H goes from 180 (cyan) → 30 (orange) → 0 (red)
  pushStyle();
  colorMode(HSB, 360, 100, 100);
  float hue = lerp(180, 0, t);
  float sat = 70 + t * 25;
  float bri = 80 + t * 15;
  color c = color(hue, sat, bri);
  popStyle();
  return c;
}

// (XY force scale moved to the global RangePanel — uses the combined XY range)
