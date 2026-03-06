// Processing 4.x - 三维磁力传感器可视化系统
// 基于矩阵算法的精确力计算 (f = K^(-1) * m)
// 原生坐标系：+X右、+Y下、+Z出屏

import processing.serial.*;
import processing.event.MouseEvent;








// ============================== 全局配置参数 ==============================
// 可视化缩放系数
final float SENSOR_VECTOR_SCALE = 40.0f; // 传感器数值到屏幕长度的缩放系数

// 串口配置
final int BAUD = 115200;
String PORT_NAME = ""; // 留空自动选择最后一个端口

// 校准配置
final int CALIBRATION_SAMPLES = 100;

// ===== 3×3 耦合矩阵 K (需要根据实际标定填入) =====
// 矩阵关系: m = K * f
// 其中 m = [mx, my, mz]^T 是磁场测量值(μT)
//      f = [fx, fy, fz]^T 是力值(N)
float[][] K = {
  {282.33f, 11.33f, -19.85f},  // kxx, kxy, kxz - X轴响应系数   后下前
  {-7.33f, -112.66f, 5.2f},  // kyx, kyy, kyz - Y轴响应系数  
  {-19.85f, 5.2f, 35.4f}   // kzx, kzy, kzz - Z轴响应系数
};

// K的逆矩阵 (将在setup中计算)
float[][] K_inv = new float[3][3];

// 显示模式切换
boolean showForce = true; // true显示力(N)，false显示磁场(μT)








// ============================== 运行时状态变量 ==============================
// 串口通信
Serial ser;
float[] latest = new float[3];    // 最新原始数据(μT)
boolean latestValid = false;
long latestMillis = 0;
long frameCounter = 0;

// 校准状态
boolean isCalibrating = true;
int calibrationCount = 0;
float[] baseline = new float[3];  // 基线值(μT)
float[] delta = new float[3];     // 差值(N或μT)
private float[] sum = new float[3];

// 相机控制
float rotX = 0, rotY = 0, rotZ = 0;
float zoom = 1.0f;

// 颜色定义
final int COL_BG = color(18);
final int COL_GRID = color(60);
final int COL_X = color(220, 80, 80);
final int COL_Y = color(80, 200, 120);
final int COL_Z = color(80, 120, 220);
final int COL_SENSOR_VEC = color(255, 200, 40);

// HUD配置
PFont hudFont;
int hudX = 20, hudY = 40;
int lineSpacing = 24, titleSpacing = 8;
int hudBG = color(0, 0, 0, 120);
int hudW = 220, hudH = 8 * lineSpacing + 3 * titleSpacing;
int hudGap = 20;








// ============================== 主程序初始化 ==============================
void settings() {
  size(1100, 720, P3D);
  smooth(8);
}

void setup() {
  setIsometricView();
  
  // 计算K的逆矩阵
  K_inv = matrixInverse3x3(K);
  println("=== 标定矩阵 K ===");
  printMatrix(K);
  println("=== 逆矩阵 K^(-1) ===");
  printMatrix(K_inv);
  
  // 初始化各模块
  serial_init();
  hud_init();
  calibration_init();
}








// ============================== 主渲染循环 ==============================
void draw() {
  background(COL_BG);
  
  // 3D场景渲染
  lights();
  pushMatrix();
  translate(width/2, height/2, 0);
  scale(zoom);
  applyCameraRotation();
  
  drawGrid(40, 20);
  drawAxes(260);
  drawSensorVector3D();
  
  popMatrix();
  
  // 2D HUD渲染
  noLights();
  hint(DISABLE_DEPTH_TEST);
  drawHUD();
  hint(ENABLE_DEPTH_TEST);
}








// ============================== 矩阵运算模块 ==============================
// 3×3矩阵求逆
float[][] matrixInverse3x3(float[][] m) {
  float det = matrixDeterminant3x3(m);
  if (abs(det) < 1e-10) {
    println("[ERROR] 矩阵行列式接近0，无法求逆！使用单位矩阵代替。");
    return new float[][]{{1,0,0},{0,1,0},{0,0,1}};
  }
  
  float[][] adj = new float[3][3];
  // 计算伴随矩阵（代数余子式矩阵的转置）
  adj[0][0] =  (m[1][1]*m[2][2] - m[1][2]*m[2][1]);
  adj[0][1] = -(m[0][1]*m[2][2] - m[0][2]*m[2][1]);
  adj[0][2] =  (m[0][1]*m[1][2] - m[0][2]*m[1][1]);
  adj[1][0] = -(m[1][0]*m[2][2] - m[1][2]*m[2][0]);
  adj[1][1] =  (m[0][0]*m[2][2] - m[0][2]*m[2][0]);
  adj[1][2] = -(m[0][0]*m[1][2] - m[0][2]*m[1][0]);
  adj[2][0] =  (m[1][0]*m[2][1] - m[1][1]*m[2][0]);
  adj[2][1] = -(m[0][0]*m[2][1] - m[0][1]*m[2][0]);
  adj[2][2] =  (m[0][0]*m[1][1] - m[0][1]*m[1][0]);
  
  // 逆矩阵 = 伴随矩阵 / 行列式
  float[][] inv = new float[3][3];
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      inv[i][j] = adj[i][j] / det;
    }
  }
  return inv;
}

// 3×3矩阵行列式
float matrixDeterminant3x3(float[][] m) {
  return m[0][0] * (m[1][1]*m[2][2] - m[1][2]*m[2][1])
       - m[0][1] * (m[1][0]*m[2][2] - m[1][2]*m[2][0])  
       + m[0][2] * (m[1][0]*m[2][1] - m[1][1]*m[2][0]);
}

// 矩阵向量乘法: result = matrix * vector
float[] matrixVectorMultiply(float[][] matrix, float[] vector) {
  float[] result = new float[3];
  for (int i = 0; i < 3; i++) {
    result[i] = 0;
    for (int j = 0; j < 3; j++) {
      result[i] += matrix[i][j] * vector[j];
    }
  }
  return result;
}

// 打印矩阵
void printMatrix(float[][] m) {
  for (int i = 0; i < 3; i++) {
    println(String.format("[%+8.4f  %+8.4f  %+8.4f]", m[i][0], m[i][1], m[i][2]));
  }
}








// ============================== 串口通信模块 ==============================
void serial_init() {
  println("=== 可用串口 ===");
  String[] ports = Serial.list();
  for (int i = 0; i < ports.length; i++) {
    println(i + ": " + ports[i]);
  }
  
  String portToUse = PORT_NAME;
  if (portToUse == null || portToUse.trim().isEmpty()) {
    if (ports.length == 0) {
      println("[Serial] 没有发现串口设备");
      return;
    }
    portToUse = ports[ports.length - 1];
    println("[Serial] 自动选择端口: " + portToUse);
  } else {
    println("[Serial] 指定端口: " + portToUse);
  }
  
  try {
    ser = new Serial(this, portToUse, BAUD);
    ser.bufferUntil('\n');
    println("[Serial] 连接成功 (baud=" + BAUD + ")");
  } catch (Exception e) {
    println("[Serial] 连接失败: " + e.getMessage());
  }
}

void serialEvent(Serial s) {
  String line = s.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  if (line.length() == 0) return;
  
  // 解析格式: X;Y;Z
  if (countChar(line, ';') != 2) return;
  
  String[] toks = split(line, ';');
  if (toks == null || toks.length != 3) return;
  
  float[] vals = new float[3];
  for (int i = 0; i < 3; i++) {
    try {
      vals[i] = Float.parseFloat(toks[i].trim());
    } catch (Exception ex) {
      return;
    }
    if (Float.isNaN(vals[i]) || Float.isInfinite(vals[i])) {
      return;
    }
  }
  
  arrayCopy(vals, latest);
  latestValid = true;
  latestMillis = millis();
  frameCounter++;
  
  processNewData(vals);
}

int countChar(String s, char c) {
  int count = 0;
  for (int i = 0; i < s.length(); i++) {
    if (s.charAt(i) == c) count++;
  }
  return count;
}








// ============================== 校准与力计算模块 ==============================
void calibration_init() {
  calibration_reset();
  println("[Calibration] 开始采集 " + CALIBRATION_SAMPLES + " 个样本进行基线校准");
}

void calibration_reset() {
  isCalibrating = true;
  calibrationCount = 0;
  for (int i = 0; i < 3; i++) {
    baseline[i] = 0;
    delta[i] = 0;
    sum[i] = 0;
  }
  println("[Calibration] 重置校准，重新采集样本...");
}

void processNewData(float[] values) {
  if (!frameIsFinite(values)) return;
  
  if (isCalibrating) {
    // 累加校准样本
    for (int i = 0; i < 3; i++) {
      sum[i] += values[i];
    }
    calibrationCount++;
    
    if (calibrationCount >= CALIBRATION_SAMPLES) {
      // 计算基线平均值
      for (int i = 0; i < 3; i++) {
        baseline[i] = sum[i] / CALIBRATION_SAMPLES;
      }
      
      // 检查基线有效性
      for (float b : baseline) {
        if (Float.isNaN(b) || Float.isInfinite(b)) {
          println("[Calibration] 基线异常，自动重置");
          calibration_reset();
          return;
        }
      }
      
      isCalibrating = false;
      println("[Calibration] 校准完成！基线值: [" + 
              nf(baseline[0], 1, 2) + ", " + 
              nf(baseline[1], 1, 2) + ", " + 
              nf(baseline[2], 1, 2) + "] μT");
    }
  } else {
    // 计算磁场变化量 Δm = m - baseline
    float[] deltaB = new float[3];
    for (int i = 0; i < 3; i++) {
      deltaB[i] = values[i] - baseline[i];
    }
    
    if (showForce) {
      // 使用逆矩阵计算力: f = K^(-1) * Δm
      float[] force = matrixVectorMultiply(K_inv, deltaB);
      arrayCopy(force, delta);
    } else {
      // 直接显示磁场变化量
      arrayCopy(deltaB, delta);
    }
  }
}

boolean frameIsFinite(float[] a) {
  if (a == null || a.length != 3) return false;
  for (float v : a) {
    if (Float.isNaN(v) || Float.isInfinite(v)) return false;
  }
  return true;
}








// ============================== HUD界面模块 ==============================
void hud_init() {
  hudFont = createFont("Consolas", 18, true);
}

void drawHUD() {
  textFont(hudFont);
  textAlign(LEFT, TOP);
  drawRawValuesPanel();
  drawDeltaPanel();
}

void drawRawValuesPanel() {
  noStroke();
  fill(hudBG);
  rect(hudX, hudY - 30, hudW, hudH, 10);
  
  fill(255);
  if (!latestValid) {
    text("等待串口数据...", hudX + 10, hudY);
    return;
  }
  
  int y = hudY;
  text("S1 Raw (μT):", hudX + 10, y);
  y += lineSpacing;
  text("  X = " + nf(latest[0], 1, 2), hudX + 10, y);
  y += lineSpacing;
  text("  Y = " + nf(latest[1], 1, 2), hudX + 10, y);
  y += lineSpacing;
  text("  Z = " + nf(latest[2], 1, 2), hudX + 10, y);
}

void drawDeltaPanel() {
  int deltaX = hudX + hudW + hudGap;
  noStroke();
  fill(hudBG);
  rect(deltaX, hudY - 30, hudW, hudH, 10);
  
  if (isCalibrating) {
    fill(255, 220, 100);
    text("校准中...", deltaX + 10, hudY);
    text("样本: " + calibrationCount + "/" + CALIBRATION_SAMPLES,
         deltaX + 10, hudY + lineSpacing);
    return;
  }
  
  int y = hudY;
  fill(255);
  String unitLabel = showForce ? "N" : "μT";
  String modeLabel = showForce ? "S1 Force" : "S1 Mag Field";
  text(modeLabel + " [" + unitLabel + "]:", deltaX + 10, y);
  
  y += lineSpacing;
  drawDeltaValue(delta[0], deltaX + 10, y, "X");
  y += lineSpacing;
  drawDeltaValue(delta[1], deltaX + 10, y, "Y");
  y += lineSpacing;
  drawDeltaValue(delta[2], deltaX + 10, y, "Z");
}

void drawDeltaValue(float val, float x, float y, String axis) {
  float absVal = abs(val);
  float norm = constrain(absVal / 500.0, 0, 1);
  
  int r = (val < 0) ? int(255 * norm) : int(255 * (1 - norm));
  int g = (val > 0) ? int(255 * norm) : int(255 * (1 - norm));
  int b = int(255 * (1 - norm));
  
  String unit = showForce ? " N" : " μT";
  fill(r, g, b);
  text("  " + axis + " = " + nfp(val, 1, 2) + unit, x, y);
}








// ============================== 3D可视化模块 ==============================
void applyCameraRotation() {
  rotateZ(rotZ);
  rotateY(rotY);
  rotateX(rotX);
}

void setIsometricView() {
  rotZ = radians(42);
  rotY = radians(-30);
  rotX = radians(30);
  zoom = 0.7f;
}

void drawGrid(int step, int count) {
  stroke(COL_GRID);
  noFill();
  for (int i = -count; i <= count; i++) {
    line(i * step, -count * step, 0, i * step, count * step, 0);
    line(-count * step, i * step, 0, count * step, i * step, 0);
  }
}

void drawAxes(float len) {
  // 正向轴
  drawArrow(new PVector(0,0,0), new PVector(len, 0, 0), COL_X, 6, "+X");
  drawArrow(new PVector(0,0,0), new PVector(0, len, 0), COL_Y, 6, "+Y");
  drawArrow(new PVector(0,0,0), new PVector(0, 0, len), COL_Z, 6, "+Z");
  
  // 负向轴
  stroke(150,70,70); strokeWeight(2); line(0,0,0, -len, 0, 0);
  stroke(70,120,70); strokeWeight(2); line(0,0,0, 0, -len, 0);
  stroke(70,70,120); strokeWeight(2); line(0,0,0, 0, 0, -len);
}

void drawSensorVector3D() {
  if (!latestValid || isCalibrating || delta == null) return;
  
  float vx = delta[0] * SENSOR_VECTOR_SCALE;
  float vy = delta[1] * SENSOR_VECTOR_SCALE;
  float vz = delta[2] * SENSOR_VECTOR_SCALE;
  
  PVector origin = new PVector(0, 0, 0);
  PVector tip = new PVector(vx, vy, vz);
  
  String label = showForce ? "Force" : "B-field";
  drawArrow(origin, tip, COL_SENSOR_VEC, 8, label);
}

void drawArrow(PVector start, PVector end, int col, float weight, String label) {
  float L = PVector.dist(start, end);
  float ah = min(40, L * 0.14f);
  float r = max(4, min(14, ah * 0.43f));
  
  PVector dir = PVector.sub(end, start).normalize(null);
  PVector lineEnd = PVector.sub(end, PVector.mult(dir, ah));
  
  stroke(col);
  strokeWeight(weight);
  line(start.x, start.y, start.z, lineEnd.x, lineEnd.y, lineEnd.z);
  
  // 箭头锥体
  pushMatrix();
  translate(end.x, end.y, end.z);
  PVector zAxis = new PVector(0, 0, 1);
  PVector axis = zAxis.cross(dir);
  float angle = acos(constrain(zAxis.dot(dir), -1, 1));
  if (axis.mag() > 1e-6) {
    axis.normalize();
    rotate(angle, axis.x, axis.y, axis.z);
  }
  noStroke();
  fill(col);
  cone(r, ah);
  popMatrix();
  
  // 标签
  pushMatrix();
  translate(end.x + dir.x*15, end.y + dir.y*15, end.z + dir.z*15);
  fill(col);
  textSize(16);
  text(label, 0, 0, 0);
  popMatrix();
}

void cone(float r, float h) {
  int seg = 24;
  beginShape(TRIANGLE_FAN);
  vertex(0, 0, 0);
  for (int i = 0; i <= seg; i++) {
    float a = TWO_PI * i / seg;
    vertex(r * cos(a), r * sin(a), -h);
  }
  endShape();
}








// ============================== 用户交互模块 ==============================
void mouseDragged() {
  if (mouseButton == LEFT) {
    rotY += (mouseX - pmouseX) * 0.01f;
    rotX += (mouseY - pmouseY) * 0.01f;
  }
}

void mouseWheel(MouseEvent e) {
  zoom *= 1.0f - e.getCount() * 0.05f;
  zoom = constrain(zoom, 0.3f, 5.0f);
}

void mousePressed() {
  if (mouseButton == RIGHT) {
    setIsometricView();
  }
}

void keyPressed() {
  if (key == 'c' || key == 'C') {
    calibration_reset();
  }
  if (key == 'f' || key == 'F') {
    showForce = !showForce;
    println("[Display] 切换显示模式: " + (showForce ? "Force (N)" : "Magnetic field (μT)"));
  }
  if (key == 'k' || key == 'K') {
    // 打印当前标定矩阵
    println("\n=== 当前标定矩阵 K ===");
    printMatrix(K);
    println("=== 逆矩阵 K^(-1) ===");
    printMatrix(K_inv);
  }
}
