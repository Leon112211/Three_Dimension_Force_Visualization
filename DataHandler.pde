// =============================================================================
// DataHandler.pde
// Arduino 串口通信、数据解析与缓冲管理模块
//
// Arduino 输出格式（Single_Sensor.ino）：
//   "1.23,-0.45,2.00\n"  — 逗号分隔的三个浮点数，无标签
//
// 依赖：DecoupleAlgorithm.pde（decouple() 函数）
// =============================================================================

import processing.serial.*;


// ========================== 可配置参数 ========================================

// 波特率（必须与 Arduino 的 Serial.begin() 一致）
static final int     BAUD_RATE          = 115200;

// 自动检测端口时匹配的关键词（Windows: "COM"；macOS/Linux: "usbmodem" 或 "ttyACM"）
static final String  PORT_KEYWORD       = "COM";

// 强制指定端口索引（-1 = 自动检测；0、1、2... = 使用 Serial.list()[N]）
static final int     PORT_FORCE_INDEX   = -1;

// 数据缓冲区大小（保留最近 N 帧数据）
static final int     BUFFER_SIZE        = 100;

// 数据合法性上限（µT），超出此范围的帧视为噪声并丢弃
static final float   MAX_SENSOR_VALUE   = 5000.0;

// Arduino 数据格式选择：
//   false → 逗号分隔无标签格式（Single_Sensor.ino 默认）: "1.23,-0.45,2.00"
//   true  → 带标签格式（如自定义 Arduino 脚本）:          "X:1.23, Y:-0.45, Z:2.00"
static final boolean USE_LABELED_FORMAT = false;

// =============================================================================


// ----------------------- 数据点类 --------------------------------------------

// 单帧数据，包含原始磁场读数和解耦后的力
class DataPoint {
  float bx, by, bz;       // 原始传感器读数（µT）
  float fx, fy, fz;       // 解耦后三轴力（N）
  long  timestamp;        // 帧时间戳（毫秒，相对于程序启动）

  DataPoint(float bx, float by, float bz,
            float fx, float fy, float fz,
            long ts) {
    this.bx = bx; this.by = by; this.bz = bz;
    this.fx = fx; this.fy = fy; this.fz = fz;
    this.timestamp = ts;
  }
}


// ----------------------- 模块内部状态 ----------------------------------------

Serial          arduinoPort;                        // 串口对象
ArrayList<DataPoint> dataBuffer = new ArrayList<>(); // 循环数据缓冲区

// 最新一帧（供各可视化模块直接读取）
float latestBx = 0, latestBy = 0, latestBz = 0;  // 原始读数（µT）
float latestFx = 0, latestFy = 0, latestFz = 0;  // 解耦后的力（N）
long  latestTimestamp = 0;

boolean serialReady   = false;  // 串口连接成功标志
int     totalReceived = 0;      // 累计成功解析的帧数
int     totalErrors   = 0;      // 累计解析失败的帧数


// =============================================================================
// initSerial()
// 初始化串口：先尝试自动检测，失败则按 PORT_FORCE_INDEX 回退。
// 必须在 setup() 中、loadCouplingMatrix() 之后调用。
// =============================================================================
void initSerial() {
  String[] ports = Serial.list();

  if (ports.length == 0) {
    println("[DataHandler] 错误：未发现任何串口设备。请检查 Arduino 连接。");
    return;
  }

  println("[DataHandler] 可用串口列表：");
  for (int i = 0; i < ports.length; i++) {
    println("  [" + i + "] " + ports[i]);
  }

  // 确定目标端口索引
  int targetIndex = _resolvePortIndex(ports);
  if (targetIndex < 0) {
    println("[DataHandler] 错误：未找到匹配端口（关键词='" + PORT_KEYWORD + "'）。");
    println("  请修改 PORT_FORCE_INDEX 或 PORT_KEYWORD 手动指定。");
    return;
  }

  // 建立串口连接
  try {
    arduinoPort = new Serial(this, ports[targetIndex], BAUD_RATE);
    arduinoPort.bufferUntil('\n'); // 以换行符为帧边界触发 serialEvent
    serialReady = true;
    println("[DataHandler] 已连接串口: " + ports[targetIndex] + " @ " + BAUD_RATE + " baud");
  } catch (Exception e) {
    println("[DataHandler] 错误：串口连接失败。");
    println("  端口: " + ports[targetIndex]);
    println("  原因: " + e.getMessage());
    println("  请确认 Arduino 已连接且未被其他程序占用（如 Arduino IDE）。");
  }
}


// =============================================================================
// serialEvent(Serial port)
// Processing 串口事件回调，每次收到一行数据时自动触发。
// 不要手动调用此函数。
// =============================================================================
void serialEvent(Serial port) {
  String line = "";
  try {
    line = port.readStringUntil('\n');
    if (line == null || line.trim().length() == 0) return;

    line = line.trim();

    // 跳过注释行（Arduino 调试输出或列名行）
    if (line.startsWith("//") || line.startsWith("#") ||
        line.startsWith("S1") || line.startsWith("Human")) return;

    // 解析数据
    float[] raw = USE_LABELED_FORMAT ? _parseLabeledFormat(line)
                                     : _parseCSVFormat(line);
    if (raw == null) return; // 解析失败，已在内部记录错误

    // 合法性检查
    if (!_isValidReading(raw)) {
      totalErrors++;
      println("[DataHandler] 警告：数据超出范围，已丢弃: " + line);
      return;
    }

    // 解耦运算（来自 DecoupleAlgorithm.pde）
    float[] force = decouple(raw);

    // 更新最新帧
    latestBx        = raw[0];   latestBy = raw[1]; latestBz = raw[2];
    latestFx        = force[0]; latestFy = force[1]; latestFz = force[2];
    latestTimestamp = millis();

    // 写入缓冲区（超出上限时移除最旧帧）
    dataBuffer.add(new DataPoint(raw[0], raw[1], raw[2],
                                 force[0], force[1], force[2],
                                 latestTimestamp));
    if (dataBuffer.size() > BUFFER_SIZE) {
      dataBuffer.remove(0);
    }

    totalReceived++;

  } catch (Exception e) {
    totalErrors++;
    println("[DataHandler] 异常：处理数据时出错。");
    println("  原始数据: \"" + line + "\"");
    println("  原因: " + e.getMessage());
  }
}


// =============================================================================
// getRawForce()
// 返回最新一帧的原始传感器读数（µT）：[Bx, By, Bz]
// =============================================================================
float[] getRawForce() {
  return new float[]{latestBx, latestBy, latestBz};
}


// =============================================================================
// getDecoupledForce()
// 返回最新一帧解耦后的三轴力（N）：[Fx, Fy, Fz]
// =============================================================================
float[] getDecoupledForce() {
  return new float[]{latestFx, latestFy, latestFz};
}


// =============================================================================
// getLatestPoint()
// 返回最新一帧完整数据（含时间戳），无新数据时返回 null
// =============================================================================
DataPoint getLatestPoint() {
  if (dataBuffer.size() == 0) return null;
  return dataBuffer.get(dataBuffer.size() - 1);
}


// =============================================================================
// getBufferCopy()
// 返回当前缓冲区的快照副本（供绘图模块遍历历史数据）
// 返回的是副本，不会因串口线程写入而产生并发问题
// =============================================================================
ArrayList<DataPoint> getBufferCopy() {
  return new ArrayList<DataPoint>(dataBuffer);
}


// =============================================================================
// getBufferSize()
// 返回缓冲区中当前实际帧数（0 ~ BUFFER_SIZE）
// =============================================================================
int getBufferSize() {
  return dataBuffer.size();
}


// =============================================================================
// printStatus()
// 打印串口和数据统计摘要（调试用，可在 draw() 中定时调用）
// =============================================================================
void printStatus() {
  println("[DataHandler] 状态摘要：");
  println("  串口就绪: " + serialReady);
  println("  已接收帧: " + totalReceived);
  println("  解析错误: " + totalErrors);
  println("  缓冲区帧: " + dataBuffer.size() + " / " + BUFFER_SIZE);
  if (totalReceived > 0) {
    println("  最新原始: [" + nf(latestBx,1,2) + ", " + nf(latestBy,1,2) + ", " + nf(latestBz,1,2) + "] µT");
    println("  最新解耦: [" + nf(latestFx,1,3) + ", " + nf(latestFy,1,3) + ", " + nf(latestFz,1,3) + "] N");
  }
}


// =============================================================================
// 以下为模块内部私有函数（函数名以 _ 前缀标识，不对外调用）
// =============================================================================

// 解析逗号分隔格式："1.23,-0.45,2.00"
float[] _parseCSVFormat(String line) {
  String[] parts = split(line, ',');
  if (parts.length != 3) {
    totalErrors++;
    println("[DataHandler] 解析失败（CSV）：期望3列，实际" + parts.length + "列。原始: \"" + line + "\"");
    return null;
  }
  try {
    return new float[]{float(parts[0].trim()), float(parts[1].trim()), float(parts[2].trim())};
  } catch (Exception e) {
    totalErrors++;
    println("[DataHandler] 解析失败（CSV转浮点）：\"" + line + "\"");
    return null;
  }
}

// 解析带标签格式："X:1.23, Y:-0.45, Z:2.00"
float[] _parseLabeledFormat(String line) {
  try {
    // 提取冒号后的数值部分
    String[] tokens = splitTokens(line, " ,");   // 按空格和逗号分割
    float[] vals = new float[3];
    int found = 0;
    for (String t : tokens) {
      if (t.indexOf(':') >= 0) {
        String[] kv = split(t, ':');
        if (kv.length == 2) {
          vals[found++] = float(kv[1].trim());
          if (found == 3) break;
        }
      }
    }
    if (found != 3) {
      totalErrors++;
      println("[DataHandler] 解析失败（标签格式）：找到" + found + "个值。原始: \"" + line + "\"");
      return null;
    }
    return vals;
  } catch (Exception e) {
    totalErrors++;
    println("[DataHandler] 解析失败（标签格式异常）：\"" + line + "\"");
    return null;
  }
}

// 检查读数是否在合法范围内
boolean _isValidReading(float[] raw) {
  for (float v : raw) {
    if (Float.isNaN(v) || Float.isInfinite(v) || abs(v) > MAX_SENSOR_VALUE) return false;
  }
  return true;
}

// 确定目标端口索引：优先 PORT_FORCE_INDEX，其次按 PORT_KEYWORD 自动匹配
int _resolvePortIndex(String[] ports) {
  if (PORT_FORCE_INDEX >= 0 && PORT_FORCE_INDEX < ports.length) {
    println("[DataHandler] 使用强制指定端口索引: " + PORT_FORCE_INDEX);
    return PORT_FORCE_INDEX;
  }
  // 自动检测：返回第一个包含关键词的端口
  for (int i = 0; i < ports.length; i++) {
    if (ports[i].indexOf(PORT_KEYWORD) >= 0) {
      println("[DataHandler] 自动匹配端口: " + ports[i]);
      return i;
    }
  }
  // 关键词未匹配时，若只有一个端口则直接使用
  if (ports.length == 1) {
    println("[DataHandler] 仅有一个端口，自动使用: " + ports[0]);
    return 0;
  }
  return -1; // 无法确定
}
