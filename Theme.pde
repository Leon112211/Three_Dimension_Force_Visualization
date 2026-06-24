// ============================================================
// Theme.pde
// Shared visual language for the instrument dashboard.
// ============================================================

color UI_BG = 0xFF171815;
color UI_PANEL = 0xFF10131B;
color UI_PANEL_2 = 0xFF141925;
color UI_PANEL_HI = 0xFF1B2433;
color UI_BORDER = 0xFF2B3A52;
color UI_BORDER_ACTIVE = 0xFF4B83F6;
color UI_GRID = 0xFF2D3442;
color UI_TEXT = 0xFFE3E9F2;
color UI_MUTED = 0xFF8791A3;
color UI_DIM = 0xFF555D6E;
color UI_WARN = 0xFFE49A45;
color UI_DANGER = 0xFFFF6D5E;
color UI_GOOD = 0xFF4EE384;

color UI_X = 0xFF5A92FF;
color UI_Y = 0xFF66E07D;
color UI_Z = 0xFFFFA23D;
color UI_RESULT = 0xFFFFF5B8;

PFont UI_FONT;
PFont UI_MONO;

void initTheme() {
  UI_FONT = createFont("Segoe UI", 14, true);
  UI_MONO = createFont("Cascadia Mono", 14, true);
  textFont(UI_FONT);
}

void useUIFont(float size) {
  if (UI_FONT != null) textFont(UI_FONT);
  textSize(size);
}

void useMonoFont(float size) {
  if (UI_MONO != null) textFont(UI_MONO);
  textSize(size);
}

void drawAppBackdrop() {
  noStroke();
  fill(UI_BG);
  rect(0, 0, DESIGN_W, DESIGN_H);
}

// Shared panel title: subtle chip on the top border + muted label.
// Used by drawPanelBase, drawPanelFrame, and MatrixHUD so every panel title
// looks identical. Chip uses UI_PANEL_HI so it shows on filled and border-only
// panels alike.
void drawPanelTitle(float x, float y, String title) {
  if (title == null || title.length() == 0) return;
  useUIFont(11);
  textAlign(LEFT, TOP);
  noStroke();
  fill(UI_PANEL_HI);
  rect(x + 12, y + 5, textWidth(title) + 12, 16, 4);
  fill(UI_MUTED);
  text(title, x + 18, y + 8);
}

void drawPanelBase(float x, float y, float w, float h, String title) {
  noStroke();
  fill(0, 0, 0, 55);
  rect(x + 2, y + 3, w, h, 8);

  fill(UI_PANEL);
  rect(x, y, w, h, 8);

  stroke(UI_BORDER);
  strokeWeight(1);
  noFill();
  rect(x + 0.5, y + 0.5, w - 1, h - 1, 8);
  noStroke();

  drawPanelTitle(x, y, title);
}

void drawPanelFrame(float x, float y, float w, float h, String title) {
  noFill();
  stroke(UI_BORDER);
  strokeWeight(1);
  rect(x + 0.5, y + 0.5, w - 1, h - 1, 8);
  noStroke();

  drawPanelTitle(x, y, title);
}

void drawBadge(float x, float y, String label, color bg, color fg) {
  useUIFont(11);
  float w = textWidth(label) + 18;
  float h = 22;
  noStroke();
  fill(bg);
  rect(x, y, w, h, 6);
  fill(fg);
  textAlign(CENTER, CENTER);
  text(label, x + w / 2, y + h / 2);
}
