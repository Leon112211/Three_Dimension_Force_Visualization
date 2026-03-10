// ============================================================
// TDF_Visual.pde — 主入口
// 三维力传感器（TDF）数据可视化
// 传感器型号：H2 / H4 / H6
// ============================================================

void setup() {
  size(900, 600);
  textSize(14);
  textAlign(LEFT, BASELINE);

  initReceiver();   // SensorReceiver.pde
  initBaseline();   // Baseline.pde — begin 3-axis calibration
}

void draw() {
  background(30);

  // 轮询串口数据（事件驱动模式下保持调用以支持未来扩展）
  updateReceiver();

  // --- connection status ---
  if (!isReceiverReady()) {
    fill(255, 80, 80);
    text("[ Serial port not connected ]  Check device and restart", 30, 40);
    return;
  }

  // --- baseline calibration (blocks normal display until done) ---
  if (newDataAvailable && !isBaselineDone()) {
    updateBaseline();
  }

  if (!isBaselineDone()) {
    drawBaselineHUD();
    newDataAvailable = false;
    return;
  }

  // --- live magnetic field readout (post-calibration) ---
  fill(180, 220, 255);
  text("Single Sensor — Live Magnetic Field (uT)", 30, 40);

  color dataColor = newDataAvailable ? color(100, 255, 150) : color(160);
  fill(dataColor);
  text("Bx = " + nf(sensorBx, 1, 3) + "   dBx = " + nf(sensorBx - baselineX, 1, 3), 30,  80);
  text("By = " + nf(sensorBy, 1, 3) + "   dBy = " + nf(sensorBy - baselineY, 1, 3), 30, 110);
  text("Bz = " + nf(sensorBz, 1, 3) + "   dBz = " + nf(sensorBz - baselineZ, 1, 3), 30, 140);

  fill(120);
  textSize(12);
  text("Baseline  Bx=" + nf(baselineX,1,3) + "  By=" + nf(baselineY,1,3) + "  Bz=" + nf(baselineZ,1,3), 30, 170);
  textSize(14);

  // consume new-data flag; visualization modules reset it themselves
  newDataAvailable = false;

  // --- TODO: call visualization drawing modules here ---
  // drawSensitivityChart();
}
