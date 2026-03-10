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
static final int TC_SIZE = 260;      // bounding square
static final float TC_R = 105.0;     // gauge circle radius (px)
static final float TC_FXY_REF = 5.0; // Fxy at which arrow reaches full length (N)

void initCompass() {
  println("[TangentialCompass] Initialized");
}

// ============================================================
void drawCompass(float fx, float fy) {
  float cx = TC_X + TC_SIZE / 2.0;
  float cy = TC_Y + TC_SIZE / 2.0;

  // --- panel background ---
  fill(20, 22, 30);
  noStroke();
  rect(TC_X, TC_Y, TC_SIZE, TC_SIZE, 6);

  // --- outer ring ---
  noFill();
  stroke(60, 65, 80);
  strokeWeight(2);
  ellipse(cx, cy, TC_R * 2, TC_R * 2);

  // thin inner ring
  stroke(45, 48, 58);
  strokeWeight(0.5);
  ellipse(cx, cy, TC_R * 1.4, TC_R * 1.4);

  // --- crosshair reference lines ---
  stroke(50, 52, 62);
  strokeWeight(0.6);
  line(cx - TC_R, cy, cx + TC_R, cy);   // horizontal
  line(cx, cy - TC_R, cx, cy + TC_R);   // vertical

  // --- tick marks around circle (every 30 deg) ---
  stroke(65, 68, 80);
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
  fill(80, 140, 255);   // X color
  text("+X", cx + TC_R + 14, cy);
  text("-X", cx - TC_R - 14, cy);
  fill(100, 220, 100);  // Y color
  text("+Y", cx, cy - TC_R - 12);
  text("-Y", cx, cy + TC_R + 12);

  // --- compute force vector ---
  float fxy = sqrt(fx * fx + fy * fy);
  float theta = atan2(fy, fx);   // angle in radians

  // --- draw center-pivot arrow if force is non-trivial ---
  if (fxy > 0.001) {
    // normalized magnitude (0..1, clamped)
    float t = constrain(fxy / TC_FXY_REF, 0, 1);

    // symmetric half-length: both sides equal, max reaches circle edge
    float halfLen  = t * TC_R;
    float frontLen = halfLen;
    float backLen  = halfLen;

    // width scales with force
    float baseW = 4.0 + t * 8.0;

    // color
    color arrowCol = tcForceColor(t);

    // direction vectors (screen: +X right, +Y up → negate sin for Y)
    float dirX =  cos(theta);
    float dirY = -sin(theta);
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
  fill(150, 155, 170);
  ellipse(cx, cy, 6, 6);

  // --- text readouts ---
  textAlign(LEFT, BASELINE);
  textSize(10);

  // magnitude
  fill(180);
  text("|Fxy| = " + nf(fxy, 1, 3) + " N", TC_X + 6, TC_Y + TC_SIZE - 20);

  // angle (degrees)
  float angleDeg = degrees(theta);
  if (angleDeg < 0) angleDeg += 360;
  text("Angle = " + nf(angleDeg, 1, 1) + " deg", TC_X + 6, TC_Y + TC_SIZE - 6);

  // --- title ---
  fill(90);
  textSize(10);
  textAlign(CENTER, TOP);
  text("XY Tangential Force", TC_X + TC_SIZE / 2, TC_Y + 3);

  // reset state
  textAlign(LEFT, BASELINE);
  textSize(14);
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
