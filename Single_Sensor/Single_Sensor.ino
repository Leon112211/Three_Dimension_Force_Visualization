// =========================================================================
// MLX90393 可视化专用版（内存优化 + 纯净输出）
// -------------------------------------------------------------------------
// 1. 内存优化：使用 F() 宏，解决 Low memory 问题。
// 2. 纯净输出：默认关闭调试文本，仅输出 "X;Y;Z" 数值，完美适配 SerialPlot。
// =========================================================================

#include <Wire.h>
#include <Adafruit_MLX90393.h>

// ------------------------- I2C 地址 ----------------------------------------
#define MLX_ADDR 0x0C

// ------------------------- 可调配置 ----------------------------------------
// 重要：设为 0 以关闭干扰文字，只输出数据供绘图软件使用
#define DEBUG_MODE   0 

#define RES_LEVEL    3
#define GAIN_LEVEL   MLX90393_GAIN_1X
#define OSR_LEVEL    MLX90393_OSR_2
#define FILTER_LEVEL MLX90393_FILTER_3

// ------------------------- 传感器实例 --------------------------------------
Adafruit_MLX90393 mlx = Adafruit_MLX90393();
bool sensor_ok = false;

static void set_all_axis_resolution(uint8_t res) {
  mlx.setResolution(MLX90393_X, res);
  mlx.setResolution(MLX90393_Y, res);
  mlx.setResolution(MLX90393_Z, res);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) delay(10);

  // 初始化 I2C
  Wire.begin();
  Wire.setClock(400000);
  Wire.setWireTimeout(1000, true);

  // 传感器初始化
  if (mlx.begin_I2C(MLX_ADDR)) {
    sensor_ok = true;
    mlx.setFilter(FILTER_LEVEL);
    mlx.setOversampling(OSR_LEVEL);
    set_all_axis_resolution(RES_LEVEL);
    mlx.setGain(GAIN_LEVEL);
  } else {
    // 如果调试模式开启，才打印错误提示，否则保持静默以免破坏绘图数据流
    #if DEBUG_MODE
      Serial.println(F("Error: Sensor offline"));
    #endif
  }

  // 可选：打印列名（有些绘图软件支持读取第一行作为图例）
  // 如果 SerialPlot 出现解析错误，可注释掉下面这行
  // Serial.println(F("X;Y;Z")); 
}

void loop() {
  float x = 0.0, y = 0.0, z = 0.0;

  if (sensor_ok) {
    // 读取数据
    mlx.readData(&x, &y, &z);
  }

  // ------------------------- 绘图软件专用输出 -------------------------
  // 格式：数值1;数值2;数值3 (换行)
  // 这是 SerialPlot 最通用的格式
  Serial.print(x, 2); 
  Serial.print(F(","));
  Serial.print(y, 2); 
  Serial.print(F(","));
  Serial.println(z, 2);

  // 如果需要调试文字，只有在 DEBUG_MODE = 1 时才输出
  #if DEBUG_MODE
    Serial.print(F("Human Debug: "));
    Serial.print(x); Serial.print(F(", "));
    Serial.println(y);
  #endif

  Serial.flush();
}