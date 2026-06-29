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
#define MLX_ADDR    0x0C    // primary/first-tried address; 0x0C..0x0F auto-scanned
#define DEBUG_MODE  0       // set to 1 to print an I2C bus scan + sensor status

// ESP32-C3 has a flexible GPIO matrix; I2C can map to any free pins.
// GPIO8 (SDA) / GPIO9 (SCL) is the common default on C3 Pro/Super Mini
// boards. Adjust here if your wiring differs.
#define I2C_SDA_PIN 8
#define I2C_SCL_PIN 9

// ---- BLE configuration --------------------------------------------------
#define BLE_DEVICE_NAME     "TDF_Sensor"
#define OUTPUT_INTERVAL_MS  10          // 100 Hz notify rate (1000 / interval)

#define NUS_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_CHAR_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // host -> device (write)
#define NUS_CHAR_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // device -> host (notify)

// ---- Globals ------------------------------------------------------------
Adafruit_MLX90393 mlx = Adafruit_MLX90393();
bool sensor_ok = false;
uint8_t  mlxAddr  = MLX_ADDR;   // resolved at runtime (0x0C..0x0F) by findMLX()
uint32_t i2cClock = 100000;     // I2C operating clock (100 kHz; findMLX may probe slower)

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

// Find the MLX with a *lightweight* raw probe (address-ACK only) across its
// 0x0C..0x0F range and 100/50 kHz. This deliberately avoids calling Adafruit's
// begin_I2C() more than once: repeatedly re-creating its I2C device on an
// unpopulated bus destabilised the BLE host (the board advertised but would not
// accept connections / reboot-looped). We do the cheap probe here, then call
// begin_I2C() exactly once on the address that actually responded.
int findMLX() {
  // 10 kHz added: on a weak-pull-up bus the slower edges are far easier to ACK
  // (RC rise time fits the longer clock period), so detection can succeed on the
  // ESP32 internal pull-ups alone. Two passes to ride out intermittent misses.
  uint32_t clocks[] = { 100000, 50000, 10000 };
  for (uint8_t pass = 0; pass < 2; pass++) {
    for (uint8_t c = 0; c < sizeof(clocks) / sizeof(clocks[0]); c++) {
      Wire.setClock(clocks[c]);
      for (uint8_t a = 0x0C; a <= 0x0F; a++) {
        yield();
        Wire.beginTransmission(a);
        if (Wire.endTransmission() == 0) {   // got an ACK -> device present
          i2cClock = clocks[c];
          return a;
        }
      }
    }
    delay(50);
  }
  return -1;
}

void setupSensor() {
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);   // proven pin init (same as before)
  Wire.setClock(100000);
  delay(50);                              // let the sensor settle after power-up

  int addr = findMLX();
  if (addr >= 0) {
    mlxAddr = (uint8_t)addr;
    Wire.setClock(i2cClock);
  }

  if (addr >= 0 && mlx.begin_I2C(mlxAddr)) {   // exactly one begin_I2C call
    sensor_ok = true;
    // Standard 100 kHz I2C (same as the original wired firmware). This relies on
    // adequate bus pull-ups; if measurement reads still come back corrupt/zero on
    // a marginal bus, drop this back to 10000 (or add 2.2k-4.7k pull-ups on
    // SDA/SCL -> 3V3). A failed read is reported as the -1 sentinel below.
    i2cClock = 100000;
    Wire.setClock(i2cClock);
    mlx.setFilter(MLX90393_FILTER_3);
    mlx.setOversampling(MLX90393_OSR_1);
    mlx.setGain(MLX90393_GAIN_1X);
    Serial.print("# Sensor ready at 0x");
    Serial.print(mlxAddr, HEX);
    Serial.print(" @ ");
    Serial.print(i2cClock / 1000);
    Serial.println(" kHz");
  } else {
    Serial.println("# Sensor not found on 0x0C-0x0F (100/50/10 kHz); streaming 0,0,0");
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

  // Give USB-CDC a moment so the one-time boot diagnostics below are not lost.
  unsigned long t0 = millis();
  while (!Serial && (millis() - t0) < 1500) delay(10);

#if DEBUG_MODE
  Serial.println("# MLX90393 BLE sensor init");
  Serial.println("# Output: NUS TX notifications, frames are x,y,z");
#endif

  setupBLE();      // advertise first so the device is always discoverable,
  setupSensor();   // even if sensor probing is slow or the bus is unpopulated
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
      if (!mlx.readData(&x, &y, &z)) {
        // Read failed on the bus this cycle -> emit a sentinel so the failure is
        // visible to the host instead of an indistinguishable silent 0,0,0.
        x = -1.0;
        y = -1.0;
        z = -1.0;
      }
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
