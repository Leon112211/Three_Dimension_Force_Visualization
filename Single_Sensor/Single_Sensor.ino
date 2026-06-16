// =========================================================================
// Single_Sensor.ino
// MLX90393 single-sensor stream for TDF_Visual.
//
// Runtime protocol for Processing:
//   x,y,z
//
// Keep DEBUG_MODE at 0 while running TDF_Visual so the serial stream contains
// only machine-readable numeric frames.
// =========================================================================

#include <Wire.h>
#include <math.h>
#include <Adafruit_MLX90393.h>

#define MLX_ADDR 0x0C
#define DEBUG_MODE 0

Adafruit_MLX90393 mlx = Adafruit_MLX90393();
bool sensor_ok = false;

bool finiteFrame(float x, float y, float z) {
  return !isnan(x) && !isnan(y) && !isnan(z)
      && !isinf(x) && !isinf(y) && !isinf(z);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) delay(10);

#if DEBUG_MODE
  Serial.println("# MLX90393 single sensor init");
  Serial.print("# I2C address: 0x");
  Serial.println(MLX_ADDR, HEX);
  Serial.println("# Output: comma-separated numeric frames (x,y,z)");
#endif

  Wire.begin();
  Wire.setClock(100000);
  Wire.setWireTimeout(1000, true);

  if (mlx.begin_I2C(MLX_ADDR)) {
    sensor_ok = true;
    mlx.setFilter(MLX90393_FILTER_3);
    mlx.setOversampling(MLX90393_OSR_1);
    mlx.setGain(MLX90393_GAIN_1X);
#if DEBUG_MODE
    Serial.println("# Sensor ready");
#endif
  } else {
#if DEBUG_MODE
    Serial.println("# Sensor not found; streaming 0,0,0");
#endif
  }
}

void loop() {
  float x = 0.0;
  float y = 0.0;
  float z = 0.0;

  if (sensor_ok) {
    mlx.readData(&x, &y, &z);
  }

  if (!finiteFrame(x, y, z)) {
#if DEBUG_MODE
    Serial.print("# Skipped invalid frame: ");
    Serial.print(x, 2);
    Serial.print(",");
    Serial.print(y, 2);
    Serial.print(",");
    Serial.println(z, 2);
#endif
    return;
  }

#if DEBUG_MODE
  Serial.print("# Sensor 0x");
  Serial.print(MLX_ADDR, HEX);
  Serial.print(": X=");
  Serial.print(x, 2);
  Serial.print(" Y=");
  Serial.print(y, 2);
  Serial.print(" Z=");
  Serial.println(z, 2);
#endif

  Serial.print(x, 2);
  Serial.print(",");
  Serial.print(y, 2);
  Serial.print(",");
  Serial.println(z, 2);
  Serial.flush();
}
