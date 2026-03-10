// ============================================================
// SensorReceiver.pde
// 负责接收 Single_Sensor 通过串口输出的 CSV 数据
// 数据格式（每行）: Bx,By,Bz
//   Bx / By / Bz — 三轴磁场值，单位 uT
// 在 TDF_Visual.pde 的 setup() 中调用 initReceiver()
// 在 TDF_Visual.pde 的 draw()  中调用 updateReceiver()
// ============================================================

import processing.serial.*;

// ---------- 串口配置（按实际情况修改） ----------
static final int   BAUD_RATE   = 115200;
static final String PORT_HINT  = "COM";    // 优先匹配含此字串的端口

// ---------- 最新一帧传感器数据 ----------
float sensorBx = 0;
float sensorBy = 0;
float sensorBz = 0;
boolean newDataAvailable = false;    // 每帧置 true，draw() 消费后可置 false

// ---------- 内部状态 ----------
Serial _port;
String _buffer = "";
boolean _receiverReady = false;

// ============================================================
// initReceiver() — 在 setup() 中调用一次
// ============================================================
void initReceiver() {
  String[] ports = Serial.list();

  if (ports.length == 0) {
    println("[SensorReceiver] No serial ports detected. Data reception disabled.");
    return;
  }

  // print all available ports for debugging
  println("[SensorReceiver] Available serial ports:");
  for (int i = 0; i < ports.length; i++) {
    println("  [" + i + "] " + ports[i]);
  }

  // auto-select first port matching PORT_HINT; fall back to last port
  String selectedPort = ports[ports.length - 1];
  for (String p : ports) {
    if (p.indexOf(PORT_HINT) >= 0) {
      selectedPort = p;
      break;
    }
  }

  try {
    _port = new Serial(this, selectedPort, BAUD_RATE);
    _port.bufferUntil('\n');    // 以换行符为帧边界触发 serialEvent()
    _receiverReady = true;
    println("[SensorReceiver] Connected: " + selectedPort + "  baud: " + BAUD_RATE);
  } catch (Exception e) {
    println("[SensorReceiver] Connection failed: " + e.getMessage());
  }
}

// ============================================================
// updateReceiver() — 在 draw() 中每帧调用
// 当前采用事件驱动（serialEvent），此函数留作扩展入口
// 例如：超时检测、帧率统计、重连逻辑等
// ============================================================
void updateReceiver() {
  // 事件驱动模式下串口数据由 serialEvent() 自动处理
  // 此处可添加超时检测等逻辑
}

// ============================================================
// serialEvent() — Processing 串口事件回调（自动触发）
// ============================================================
void serialEvent(Serial port) {
  if (port != _port) return;

  String line = port.readStringUntil('\n');
  if (line == null) return;

  line = trim(line);
  if (line.length() == 0) return;

  parseCSVLine(line);
}

// ============================================================
// parseCSVLine() — 解析一行 CSV 数据
// 支持格式：
//   3列  →  Bx,By,Bz
//   4列  →  SensorID,Bx,By,Bz  （SensorID 为字符串，忽略）
//   6列  →  Bx,By,Bz,Fx,Fy,Fz （后三列为施力，暂不使用）
// ============================================================
void parseCSVLine(String line) {
  String[] parts = split(line, ',');

  try {
    if (parts.length == 3) {
      // 格式: Bx,By,Bz
      sensorBx = float(trim(parts[0]));
      sensorBy = float(trim(parts[1]));
      sensorBz = float(trim(parts[2]));
      newDataAvailable = true;

    } else if (parts.length == 4) {
      // 格式: SensorID,Bx,By,Bz
      sensorBx = float(trim(parts[1]));
      sensorBy = float(trim(parts[2]));
      sensorBz = float(trim(parts[3]));
      newDataAvailable = true;

    } else if (parts.length >= 6) {
      // 格式: Bx,By,Bz,Fx,Fy,Fz
      sensorBx = float(trim(parts[0]));
      sensorBy = float(trim(parts[1]));
      sensorBz = float(trim(parts[2]));
      newDataAvailable = true;

    } else {
      println("[SensorReceiver] Unrecognized format (" + parts.length + " cols): " + line);
    }
  } catch (Exception e) {
    println("[SensorReceiver] Parse error: " + line + " -> " + e.getMessage());
  }
}

// ============================================================
// 工具函数：查询接收器是否就绪
// ============================================================
boolean isReceiverReady() {
  return _receiverReady;
}
