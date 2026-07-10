// ============================================================
// CsvExport.pde
// Manual CSV recording of the live data stream.
//
// REC button (top HUD, left of SOURCE) starts a recording; STOP
// closes it and pops a name dialog. Rows are appended on the DATA
// thread (serialEvent / BLE reader via parseCSVLine), so the file
// captures the full sample rate, not the 60 FPS draw rate.
//
// THREADING: the name dialog is Swing and MUST NOT run on the
// animation thread — a modal AWT dialog there deadlocks against the
// NEWT (P2D) window on Windows. stopCsvExport() therefore closes the
// writer synchronously (fast) and shows the dialog asynchronously on
// the AWT EDT via SwingUtilities.invokeLater; the sketch keeps
// drawing while the user types. The rename happens after the dialog
// returns. While the dialog is pending the REC button shows SAVING
// and a new recording cannot start (prevents tmp-file races).
//
// Files live in sketch/csv_export/ (created on demand). Each
// recording writes to a unique rec_<timestamp>.tmp.csv and is
// renamed to the chosen name on stop. Cancelling the dialog keeps
// the default timestamp name (data is never discarded).
//
// Columns:
//   epoch_ms  - absolute wall-clock time (System.currentTimeMillis)
//   t_ms      - ms since recording started
//   Bx/By/Bz_uT    - raw field
//   dBx/dBy/dBz_uT - baseline-subtracted field
//   Fx/Fy/Fz_N     - decoupled force (same math as computeForce)
// ============================================================

boolean csvRecording = false;
boolean _csvNamingPending = false;   // STOP clicked, name dialog still open
java.io.PrintWriter _csvWriter = null;
final Object _csvLock = new Object();
int _csvRows = 0;
int _csvStartMs = 0;
String _csvTmpPath = null;
boolean _csvHookAdded = false;

// --- REC button (row 1 of the top-HUD control column) ---
static final int REC_BTN_W = HUD_BTN_W;
static final int REC_BTN_H = HUD_BTN_H;
static final int REC_BTN_X = HUD_BTN_X;
static final int REC_BTN_Y = HUD_BTN_Y0;

boolean isRecButtonHit(float mx, float my) {
  return mx >= REC_BTN_X && mx <= REC_BTN_X + REC_BTN_W &&
         my >= REC_BTN_Y && my <= REC_BTN_Y + REC_BTN_H;
}

void drawRecButton(boolean hover) {
  color base = csvRecording ? color(122, 40, 38) : UI_PANEL_HI;
  noStroke();
  fill(hover ? lerpColor(base, color(255, 255, 255), 0.15) : base);
  rect(REC_BTN_X, REC_BTN_Y, REC_BTN_W, REC_BTN_H, 6);

  if (csvRecording) {
    if ((frameCount / 30) % 2 == 0) {   // blinking dot
      fill(UI_DANGER);
      ellipse(REC_BTN_X + 15, REC_BTN_Y + REC_BTN_H / 2.0, 8, 8);
    }
    fill(UI_TEXT);
    useUIFont(13);
    textAlign(CENTER, CENTER);
    int sec = (millis() - _csvStartMs) / 1000;
    text("STOP " + sec + "s",
         REC_BTN_X + REC_BTN_W / 2.0, REC_BTN_Y + REC_BTN_H / 2.0 + 1);
  } else {
    fill(_csvNamingPending ? UI_MUTED : UI_TEXT);
    useUIFont(13);
    textAlign(CENTER, CENTER);
    text(_csvNamingPending ? "SAVING" : "REC",
         REC_BTN_X + REC_BTN_W / 2.0, REC_BTN_Y + REC_BTN_H / 2.0 + 1);
  }

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

// ============================================================
// Start / stop
// ============================================================
void startCsvExport() {
  if (_csvNamingPending) {
    println("[CsvExport] Finish naming the previous recording first.");
    return;
  }

  File dir = new File(sketchPath("csv_export"));
  if (!dir.exists() && !dir.mkdirs()) {
    println("[CsvExport] ERROR: could not create csv_export/ folder.");
    return;
  }

  // Rescue *.tmp.csv leftovers from sessions that died mid-recording.
  // (No live tmp can exist here: recording is off and no naming is pending.)
  File[] files = dir.listFiles();
  if (files != null) {
    int r = 0;
    for (File f : files) {
      if (f.getName().endsWith(".tmp.csv")) {
        File rescued = new File(dir,
          "recovered_" + csvTimestamp() + (r > 0 ? "_" + r : "") + ".csv");
        if (f.renameTo(rescued)) {
          println("[CsvExport] Rescued unfinished recording -> " + rescued.getName());
          r++;
        }
      }
    }
  }

  String tmp = new File(dir, "rec_" + csvTimestamp() + ".tmp.csv").getAbsolutePath();

  synchronized (_csvLock) {
    try {
      _csvWriter = new java.io.PrintWriter(
        new java.io.BufferedWriter(new java.io.FileWriter(tmp)));
    } catch (Exception e) {
      println("[CsvExport] ERROR: cannot open file: " + e.getMessage());
      _csvWriter = null;
      return;
    }
    _csvWriter.println("epoch_ms,t_ms,Bx_uT,By_uT,Bz_uT,dBx_uT,dBy_uT,dBz_uT,Fx_N,Fy_N,Fz_N");
    _csvTmpPath = tmp;
    _csvRows = 0;
    _csvStartMs = millis();
    csvRecording = true;
  }
  addCsvShutdownHook();
  println("[CsvExport] Recording started (" + SENSOR_NAMES[activeSensor] + ").");
}

// askName=true  -> async name dialog on the AWT EDT (manual STOP click)
// askName=false -> silent save with timestamp name (source switch / app exit)
void stopCsvExport(boolean askName) {
  String tmpPathLocal;
  int rowsLocal;
  synchronized (_csvLock) {
    if (_csvWriter == null) return;
    csvRecording = false;
    _csvWriter.flush();
    _csvWriter.close();
    _csvWriter = null;
    tmpPathLocal = _csvTmpPath;
    _csvTmpPath = null;
    rowsLocal = _csvRows;
  }
  if (tmpPathLocal == null) return;

  final String tmpPath = tmpPathLocal;
  final int rows = rowsLocal;
  final String defName = "TDF_" + csvTimestamp();

  if (!askName) {
    finalizeCsvFile(tmpPath, defName, rows);
    return;
  }

  // Dialog runs on the AWT EDT — never block the animation thread.
  _csvNamingPending = true;
  javax.swing.SwingUtilities.invokeLater(new Runnable() {
    public void run() {
      String name = defName;
      try {
        // Invisible always-on-top parent forces the dialog in front of
        // the (NEWT) sketch window instead of opening behind it.
        javax.swing.JFrame front = new javax.swing.JFrame();
        front.setUndecorated(true);
        front.setAlwaysOnTop(true);
        front.setLocationRelativeTo(null);
        front.setVisible(true);
        String input = javax.swing.JOptionPane.showInputDialog(front,
          "Recording finished (" + rows + " rows).\nFile name:", defName);
        front.dispose();
        if (input != null) {
          input = sanitizeCsvName(input);
          if (input.length() > 0) name = input;
        }
        // null (Cancel) -> keep the default timestamp name; never discard data
      } catch (Exception e) {
        println("[CsvExport] Name dialog failed (" + e.getMessage()
                + "); using default name.");
      }
      finalizeCsvFile(tmpPath, name, rows);
      _csvNamingPending = false;
    }
  });
}

// Rename the tmp file to its final name (collision-safe).
void finalizeCsvFile(String tmpPath, String name, int rows) {
  if (!name.toLowerCase().endsWith(".csv")) name += ".csv";
  File dir = new File(sketchPath("csv_export"));
  File target = new File(dir, name);
  String stem = name.substring(0, name.length() - 4);
  int k = 2;
  while (target.exists()) {   // name.csv -> name_2.csv, name_3.csv ...
    target = new File(dir, stem + "_" + k + ".csv");
    k++;
  }

  File tmpFile = new File(tmpPath);
  if (tmpFile.renameTo(target)) {
    println("[CsvExport] Saved " + rows + " rows -> csv_export/" + target.getName());
  } else {
    println("[CsvExport] WARNING: rename failed; data kept in " + tmpFile.getName());
  }
}

// ============================================================
// Row append — called from the data thread (parseCSVLine) for every
// valid frame, so the CSV runs at the full sample rate.
// ============================================================
void csvRecordRow(float bx, float by, float bz) {
  if (!csvRecording || !isBaselineDone()) return;

  float dx = bx - baselineX;
  float dy = by - baselineY;
  float dz = bz - baselineZ;
  // same math as computeForce(), but kept local so the recorder never
  // touches the displayed forceX/Y/Z globals
  float[][] D = D_ALL[activeSensor];
  float fx = D[0][0] * dx + D[0][1] * dy + D[0][2] * dz;
  float fy = D[1][0] * dx + D[1][1] * dy + D[1][2] * dz;
  float fz = max(0, D[2][0] * dx + D[2][1] * dy + D[2][2] * dz);

  String row = String.format(java.util.Locale.US,
    "%d,%d,%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f",
    System.currentTimeMillis(), millis() - _csvStartMs,
    bx, by, bz, dx, dy, dz, fx, fy, fz);

  synchronized (_csvLock) {
    if (_csvWriter == null) return;
    _csvWriter.println(row);
    _csvRows++;
  }
}

// ============================================================
// Helpers
// ============================================================
String csvTimestamp() {
  return new java.text.SimpleDateFormat("yyyyMMdd_HHmmss")
    .format(new java.util.Date());
}

// strip characters Windows forbids in file names
String sanitizeCsvName(String s) {
  s = s.trim().replaceAll("[\\\\/:*?\"<>|]", "_");
  while (s.endsWith(".") || s.endsWith(" ")) s = s.substring(0, s.length() - 1);
  return s;
}

// flush + save with a timestamp name if the sketch exits mid-recording
void addCsvShutdownHook() {
  if (_csvHookAdded) return;
  _csvHookAdded = true;
  Runtime.getRuntime().addShutdownHook(new Thread(new Runnable() {
    public void run() { stopCsvExport(false); }
  }));
}
