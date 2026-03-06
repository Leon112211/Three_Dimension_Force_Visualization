// =========================================================================
// MLX90393 四传感器可视化（仅注释重写，逻辑不变）
// -------------------------------------------------------------------------
// 概要：
// - I2C 同总线上挂 4 颗 MLX90393，地址为 0x0C~0x0F（由 A0/A1 组合决定）。
// - 每颗传感器统一配置：数字滤波等级=3、过采样=1、增益=MLX90393_GAIN_5X。
// - 健壮初始化：逐颗 begin，记录在线状态；离线传感器输出 0。
// - 输出两类串口数据：
//   (1) DEBUG_MODE=1 时，打印人类可读的调试信息；
//   (2) 无论是否调试，都以“分号分隔”的 12 个数值流，适配 Serial Plotter。
// - 数值保留 2 位小数；单位沿用库默认（通常为 µT）。
// =========================================================================

#include <Wire.h>
#include <Adafruit_MLX90393.h>

// ------------------------- I2C 地址（由 A0/A1 决定） -------------------------
#define ADDR_SENSOR_1 0x0C // A0=0, A1=0
#define ADDR_SENSOR_2 0x0D // A0=1, A1=0
#define ADDR_SENSOR_3 0x0E // A0=0, A1=1
#define ADDR_SENSOR_4 0x0F // A0=1, A1=1

// ------------------------- 调试开关 -------------------------
// 1：打印详细调试信息（初始化结果、每次读数等）
// 0：仅输出给 Serial Plotter 的数据流
#define DEBUG_MODE 1

// ------------------------- 传感器实例 -------------------------
Adafruit_MLX90393 mlx1 = Adafruit_MLX90393();
Adafruit_MLX90393 mlx2 = Adafruit_MLX90393();
Adafruit_MLX90393 mlx3 = Adafruit_MLX90393();
Adafruit_MLX90393 mlx4 = Adafruit_MLX90393();

// ------------------------- 在线状态标志 -------------------------
// 对应 begin_I2C 成功与否；离线时该通道数据固定输出 0
bool sensor1_ok = false;
bool sensor2_ok = false;
bool sensor3_ok = false;
bool sensor4_ok = false;

void setup() {
  // 串口初始化
  Serial.begin(115200);
  while (!Serial) delay(10);

#if DEBUG_MODE
  Serial.println("=====================================");
  Serial.println("MLX90393 四传感器初始化（健壮模式）");
  Serial.println("统一配置：FILTER=3, OSR=1, GAIN=MLX90393_GAIN_5X");
  Serial.println("输出：调试信息 + 12通道分号分隔数据流");
  Serial.println("=====================================");
#endif

//////////////////////////////////////////
  Wire.begin();                 // 显式启动 I²C
  Wire.setClock(100000);        // 先用 100kHz（更稳），后面再升 400kHz 也可
  Wire.setWireTimeout(1000, true); // 1s 超时，防止 I²C 硬卡死

  // ------------------------- 逐颗初始化 + 统一配置 -------------------------
  if (mlx1.begin_I2C(ADDR_SENSOR_1)) {
    sensor1_ok = true;
    mlx1.setFilter(MLX90393_FILTER_3);
    mlx1.setOversampling(MLX90393_OSR_1);
    mlx1.setGain(MLX90393_GAIN_5X);
#if DEBUG_MODE
    Serial.print("传感器 1 (0x"); Serial.print(ADDR_SENSOR_1, HEX); Serial.println(") 就绪");
#endif
  } else {
#if DEBUG_MODE
    Serial.print("未发现传感器 1 (0x"); Serial.print(ADDR_SENSOR_1, HEX); Serial.println(")");
#endif
  }

  if (mlx2.begin_I2C(ADDR_SENSOR_2)) {
    sensor2_ok = true;
    mlx2.setFilter(MLX90393_FILTER_3);
    mlx2.setOversampling(MLX90393_OSR_1);
    mlx2.setGain(MLX90393_GAIN_5X);
#if DEBUG_MODE
    Serial.print("传感器 2 (0x"); Serial.print(ADDR_SENSOR_2, HEX); Serial.println(") 就绪");
#endif
  } else {
#if DEBUG_MODE
    Serial.print("未发现传感器 2 (0x"); Serial.print(ADDR_SENSOR_2, HEX); Serial.println(")");
#endif
  }

  if (mlx3.begin_I2C(ADDR_SENSOR_3)) {
    sensor3_ok = true;
    mlx3.setFilter(MLX90393_FILTER_3);
    mlx3.setOversampling(MLX90393_OSR_1);
    mlx3.setGain(MLX90393_GAIN_5X);
#if DEBUG_MODE
    Serial.print("传感器 3 (0x"); Serial.print(ADDR_SENSOR_3, HEX); Serial.println(") 就绪");
#endif
  } else {
#if DEBUG_MODE
    Serial.print("未发现传感器 3 (0x"); Serial.print(ADDR_SENSOR_3, HEX); Serial.println(")");
#endif
  }

  if (mlx4.begin_I2C(ADDR_SENSOR_4)) {
    sensor4_ok = true;
    mlx4.setFilter(MLX90393_FILTER_3);
    mlx4.setOversampling(MLX90393_OSR_1);
    mlx4.setGain(MLX90393_GAIN_5X);
#if DEBUG_MODE
    Serial.print("传感器 4 (0x"); Serial.print(ADDR_SENSOR_4, HEX); Serial.println(") 就绪");
#endif
  } else {
#if DEBUG_MODE
    Serial.print("未发现传感器 4 (0x"); Serial.print(ADDR_SENSOR_4, HEX); Serial.println(")");
#endif
  }

#if DEBUG_MODE
  Serial.println("=====================================");
  Serial.println("初始化完成，开始读取数据...");
#endif

  // ------------------------- Plotter 标题行（始终输出） -------------------------
  // 始终输出 12 列标题，分号分隔，便于 Serial Plotter 识别列
  Serial.println("S1_X;S1_Y;S1_Z;S2_X;S2_Y;S2_Z;S3_X;S3_Y;S3_Z;S4_X;S4_Y;S4_Z");
}

void loop() {
  // ------------------------- 预设默认值（离线=0） -------------------------
  float x1 = 0.0, y1 = 0.0, z1 = 0.0;
  float x2 = 0.0, y2 = 0.0, z2 = 0.0;
  float x3 = 0.0, y3 = 0.0, z3 = 0.0;
  float x4 = 0.0, y4 = 0.0, z4 = 0.0;

  // ------------------------- 条件读取（仅对在线通道） -------------------------
  if (sensor1_ok) mlx1.readData(&x1, &y1, &z1);
  if (sensor2_ok) mlx2.readData(&x2, &y2, &z2);
  if (sensor3_ok) mlx3.readData(&x3, &y3, &z3);
  if (sensor4_ok) mlx4.readData(&x4, &y4, &z4);

  // ------------------------- 调试信息（可读性输出） -------------------------
#if DEBUG_MODE
  Serial.println("-------------------------------------");

  Serial.print("Sensor 1 (A0=0, A1=0): ");
  if (sensor1_ok) {
    Serial.print("X:"); Serial.print(x1, 2); Serial.print(", ");
    Serial.print("Y:"); Serial.print(y1, 2); Serial.print(", ");
    Serial.print("Z:"); Serial.print(z1, 2); Serial.println();
  } else {
    Serial.println("离线");
  }

  Serial.print("Sensor 2 (A0=1, A1=0): ");
  if (sensor2_ok) {
    Serial.print("X:"); Serial.print(x2, 2); Serial.print(", ");
    Serial.print("Y:"); Serial.print(y2, 2); Serial.print(", ");
    Serial.print("Z:"); Serial.print(z2, 2); Serial.println();
  } else {
    Serial.println("离线");
  }

  Serial.print("Sensor 3 (A0=0, A1=1): ");
  if (sensor3_ok) {
    Serial.print("X:"); Serial.print(x3, 2); Serial.print(", ");
    Serial.print("Y:"); Serial.print(y3, 2); Serial.print(", ");
    Serial.print("Z:"); Serial.print(z3, 2); Serial.println();
  } else {
    Serial.println("离线");
  }

  Serial.print("Sensor 4 (A0=1, A1=1): ");
  if (sensor4_ok) {
    Serial.print("X:"); Serial.print(x4, 2); Serial.print(", ");
    Serial.print("Y:"); Serial.print(y4, 2); Serial.print(", ");
    Serial.print("Z:"); Serial.print(z4, 2); Serial.println();
  } else {
    Serial.println("离线");
  }
#endif

  // ------------------------- 数据流（固定 12 列；分号分隔） -------------------------
  // 即使某通道离线也会输出 0，从而保持列数与顺序不变，方便 Plotter 画图
  Serial.print(x1, 2); Serial.print(";");
  Serial.print(y1, 2); Serial.print(";");
  Serial.print(z1, 2); Serial.print(";");
  Serial.print(x2, 2); Serial.print(";");
  Serial.print(y2, 2); Serial.print(";");
  Serial.print(z2, 2); Serial.print(";");
  Serial.print(x3, 2); Serial.print(";");
  Serial.print(y3, 2); Serial.print(";");
  Serial.print(z3, 2); Serial.print(";");
  Serial.print(x4, 2); Serial.print(";");
  Serial.print(y4, 2); Serial.print(";");
  Serial.println(z4, 2);

  // 确保缓冲区数据及时发送
  Serial.flush();

  // 注：readData() 内部已处理必要等待；无须额外 delay() 以获得最大采样速率
}
