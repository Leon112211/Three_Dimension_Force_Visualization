// =========================================================================
// BLE_Arduino.ino
// MLX90393 single-sensor stream for TDF_Visual over Bluetooth Low Energy.
//
// Target board: ESP32-C3 (e.g. "ESP32-C3 Pro Mini" / "Super Mini").
//
// This is the wireless counterpart to Single_Sensor.ino. It keeps the SAME
// sensor configuration and the SAME text protocol:
//
//   x,y,z\n        (field strength in uT, 2 decimals, comma-separated)
//
// ...but transmits each frame as a BLE notification instead of over USB
// serial. It exposes a Nordic UART Service (NUS) so any standard BLE-to-UART
// bridge, phone app (e.g. "nRF Connect", "Serial Bluetooth Terminal"), or a
// custom host can subscribe to the TX characteristic and read the stream.
//
// Nordic UART Service UUIDs:
//   Service : 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
//   TX char : 6E400003-B5A3-F393-E0A9-E50E24DCCA9E  (device -> host, NOTIFY)
//   RX char : 6E400002-B5A3-F393-E0A9-E50E24DCCA9E  (host -> device, WRITE)
//
// Subscribe to TX (notifications) to receive the "x,y,z" frames. The RX
// characteristic is optional and currently only used for debug echo.
//
// Required libraries:
//   - Adafruit_MLX90393  (same as Single_Sensor.ino)
//   - ESP32 BLE Arduino  (bundled with the esp32 Arduino board package)
//
// Keep DEBUG_MODE at 0 while running TDF_Visual so the BLE stream contains
// only machine-readable numeric frames. Debug text (when enabled) is printed
// to USB serial only and never mixed into the BLE notifications.
// =========================================================================

#include <Wire.h>
#include <math.h>
#include <Adafruit_MLX90393.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ---- Sensor configuration (must match Single_Sensor.ino) ----------------
#define MLX_ADDR    0x0C
#define DEBUG_MODE  0

// ESP32-C3 has a flexible GPIO matrix; I2C can map to any free pins.
// GPIO8 (SDA) / GPIO9 (SCL) is the common default on C3 Pro/Super Mini
// boards. Adjust here if your wiring differs.
#define I2C_SDA_PIN 8
#define I2C_SCL_PIN 9

// ---- BLE configuration --------------------------------------------------
#define BLE_DEVICE_NAME     "TDF_Sensor"
#define OUTPUT_INTERVAL_MS  20          // ~50 Hz notify rate; raise if BLE chokes

#define NUS_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_CHAR_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // host -> device (write)
#define NUS_CHAR_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // device -> host (notify)

// ---- Globals ------------------------------------------------------------
Adafruit_MLX90393 mlx = Adafruit_MLX90393();
bool sensor_ok = false;

BLEServer*         bleServer    = nullptr;
BLECharacteristic* txCharacteristic = nullptr;
bool deviceConnected    = false;
bool oldDeviceConnected = false;
unsigned long lastOutputMs = 0;

bool finiteFrame(float x, float y, float z) {
  return !isnan(x) && !isnan(y) && !isnan(z)
      && !isinf(x) && !isinf(y) && !isinf(z);
}

// Track central connect/disconnect so we can pause streaming and re-advertise.
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    deviceConnected = true;
#if DEBUG_MODE
    Serial.println("# BLE central connected");
#endif
  }
  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
#if DEBUG_MODE
    Serial.println("# BLE central disconnected");
#endif
  }
};

// Optional: receive commands from the host on the RX characteristic.
// Currently only echoed to USB serial in debug builds; the protocol is
// otherwise one-way (sensor -> host).
class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
#if DEBUG_MODE
    String value = characteristic->getValue();
    if (value.length() > 0) {
      Serial.print("# BLE RX: ");
      Serial.println(value);
    }
#endif
  }
};

void setupSensor() {
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(100000);
  // Note: AVR's Wire.setWireTimeout() does not exist on the ESP32 core
  // (the ESP-IDF I2C driver handles bus timeout/recovery internally), so it
  // is intentionally omitted here.

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

void setupBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);

  // Request a larger MTU so full "x,y,z\n" frames fit in a single
  // notification even for large readings (default 23-byte MTU = 20 payload
  // bytes, which can truncate frames like "-1234.56,-1234.56,-1234.56").
  BLEDevice::setMTU(185);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  BLEService* service = bleServer->createService(NUS_SERVICE_UUID);

  // TX: device -> host, notifications carry the sensor frames.
  txCharacteristic = service->createCharacteristic(
      NUS_CHAR_TX_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  txCharacteristic->addDescriptor(new BLE2902());

  // RX: host -> device, optional command channel.
  BLECharacteristic* rxCharacteristic = service->createCharacteristic(
      NUS_CHAR_RX_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rxCharacteristic->setCallbacks(new RxCallbacks());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(NUS_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);  // helps iOS discovery
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

#if DEBUG_MODE
  Serial.print("# BLE advertising as '");
  Serial.print(BLE_DEVICE_NAME);
  Serial.println("'. Subscribe to the NUS TX characteristic for x,y,z frames.");
#endif
}

void setup() {
  Serial.begin(115200);

#if DEBUG_MODE
  // Give USB-CDC a moment so early debug lines are not lost.
  unsigned long t0 = millis();
  while (!Serial && (millis() - t0) < 2000) delay(10);
  Serial.println("# MLX90393 BLE sensor init");
  Serial.print("# I2C address: 0x");
  Serial.println(MLX_ADDR, HEX);
  Serial.println("# Output: NUS TX notifications, frames are x,y,z");
#endif

  setupSensor();
  setupBLE();
}

void loop() {
  // Throttle to a BLE-friendly notification rate.
  unsigned long now = millis();
  if (now - lastOutputMs < OUTPUT_INTERVAL_MS) {
    // Still service reconnects between samples.
  } else {
    lastOutputMs = now;

    float x = 0.0;
    float y = 0.0;
    float z = 0.0;

    if (sensor_ok) {
      mlx.readData(&x, &y, &z);
    }

    if (finiteFrame(x, y, z)) {
      char frame[48];
      int n = snprintf(frame, sizeof(frame), "%.2f,%.2f,%.2f\n", x, y, z);

      if (deviceConnected && txCharacteristic != nullptr && n > 0) {
        txCharacteristic->setValue((uint8_t*)frame, n);
        txCharacteristic->notify();
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
    } else {
#if DEBUG_MODE
      Serial.print("# Skipped invalid frame: ");
      Serial.print(x, 2);
      Serial.print(",");
      Serial.print(y, 2);
      Serial.print(",");
      Serial.println(z, 2);
#endif
    }
  }

  // Re-advertise after a central drops, so a new host can reconnect.
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);  // let the BLE stack settle before re-advertising
    bleServer->startAdvertising();
    oldDeviceConnected = deviceConnected;
#if DEBUG_MODE
    Serial.println("# Re-advertising");
#endif
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }
}
