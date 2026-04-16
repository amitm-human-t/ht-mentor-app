#include <Arduino_BMI270_BMM150.h>
#include <ArduinoBLE.h>
#include <MadgwickAHRS.h>
#include <string.h>
#include <cstdint>
#include <math.h>

// Orientation derived from the Arduino Madgwick AHRS filter fed by BMI270/BMM150 samples
Madgwick orientationFilter;
float device_roll = 0.0f;
float device_pitch = 0.0f;
float device_yaw = 0.0f;
const unsigned long FAST_BLE_INTERVAL_MS = 20; // 50 Hz
const unsigned long SLOW_BLE_INTERVAL_MS = 100; // 10 Hz
unsigned long lastFastSend = 0;
unsigned long lastSlowSend = 0;
uint16_t packet_seq = 0;
unsigned long lastOrientationUpdateMicros = 0;

// sign function
#define sgn(x) ((x) < 0 ? -1 : ((x) > 0 ? 1 : 0))

constexpr uint8_t START_FLAG_BYTE = 0x7E;
constexpr uint8_t STOP_FLAG_BYTE  = 0xAE;
constexpr uint8_t ESC_BYTE        = 0x7D;

constexpr int32_t MAX_INT32 = 2147483647;

constexpr uint8_t RX_FLAG = 0x1A;
constexpr uint8_t TX_FLAG = 0x1B;

constexpr uint8_t OPCODE_REALTIME = 0x01;
constexpr uint8_t OPCODE_INFO     = 0x02;
constexpr uint8_t OPCODE_LED      = 0x03;


typedef struct __packed {
  uint16_t seq;              // 2
  int16_t IMUValues[3];      // 8
  uint16_t RollRange;        // 10
  int16_t JOYValues[4];      // 18
  int8_t  FUValues[2];       // 20
  uint8_t SysState;          // 21
  uint8_t LockState;         // 22
  uint8_t CouplingState;     // 23
  uint8_t InvertMode;        // 24
  uint8_t ButtonEvent[3];    // 27
  uint8_t ButtonNumberEvents[3]; // 30
  uint8_t ButtonState[3];    // 33
} HandXDeviceData;

typedef struct __packed {
  uint16_t seq;              // 2
  int16_t IMUValues[3];      // 8
  int16_t JOYValues[4];      // 16
  int16_t FUValues[2];       // 20
} BLEFastData;

typedef struct __packed {
  uint16_t seq;              // 2
  uint16_t RollRange;        // 4
  uint8_t SysState;          // 5
  uint8_t LockState;         // 6
  uint8_t CouplingState;     // 7
  uint8_t InvertMode;        // 8
  uint8_t ButtonEvent[3];    // 11
  uint8_t ButtonNumberEvents[3]; // 14
  uint8_t ButtonState[3];    // 17
} BLESlowData;

typedef struct __packed {
  char      version[12];
  char      dongle_sn[12];
  uint32_t  handx_sn;

} BLESystemInfo;

typedef struct __packed {
  uint8_t rx_tx_code;
  uint8_t opcode;
  uint8_t length;

} BLEHeader;


#define NANO_33_BLE_SERVICE_UUID(val) ("dd90ec52-" val "-4357-891a-26d580f709ef")

#define FAST_DATA_CHAR_UUID NANO_33_BLE_SERVICE_UUID("2001")
#define SLOW_DATA_CHAR_UUID NANO_33_BLE_SERVICE_UUID("2002")

BLEService InfoService(NANO_33_BLE_SERVICE_UUID("0000"));
BLECharacteristic infoCharacteristic(NANO_33_BLE_SERVICE_UUID("1003"), BLENotify, sizeof(BLEHeader) + sizeof(BLESystemInfo) + 1);
BLECharacteristic FastDataCharacteristic(FAST_DATA_CHAR_UUID, BLENotify, sizeof(BLEFastData));
BLECharacteristic SlowDataCharacteristic(SLOW_DATA_CHAR_UUID, BLENotify, sizeof(BLEHeader) + sizeof(BLESlowData) + 1);
BLEByteCharacteristic LEDswitchCharacteristic(NANO_33_BLE_SERVICE_UUID("1004"), BLEWriteWithoutResponse);
BLEByteCharacteristic InfoRequestCharacteristic(NANO_33_BLE_SERVICE_UUID("1005"), BLEWriteWithoutResponse);

// Orientation is estimated locally from raw BMI270/BMM150 data

char dongle_SN[12] = "0";

char handx_SN[8] = "0";
char handx_version[12] = "0";

static inline bool is_start_byte(uint8_t cur_byte, uint8_t prev_byte) {
  return (cur_byte == START_FLAG_BYTE && prev_byte != ESC_BYTE);
}

static inline bool is_stop_byte(uint8_t cur_byte, uint8_t prev_byte) {
  return (cur_byte == STOP_FLAG_BYTE && prev_byte != ESC_BYTE);
}

static float normalize_angle(float angle) {
  while (angle > 180.0f) {
    angle -= 360.0f;
  }
  while (angle < -180.0f) {
    angle += 360.0f;
  }
  return angle;
}

static int16_t clamp_angle_deg(float angle) {
  if (angle > 180.0f) angle = 180.0f;
  else if (angle < -180.0f) angle = -180.0f;
  return (int16_t)lround(angle);
}


int8_t cala_crc(uint8_t *crc_buff_in, uint16_t crc_buff_in_length) {
  uint16_t i;
  int8_t crc = 0xFF;

  for (i = 0; i < crc_buff_in_length; i++) {
    // simple xor of all bytes
    crc = crc ^ crc_buff_in[i];
  }
  // return not of solution
  return ~crc;
}


uint16_t crc16(uint8_t *pData, uint16_t length) 
{              
  uint16_t crc = 0xFFFF;
  for (uint16_t i = 0; i < length; i++) { crc ^= pData[i]; }         // Simple xor of all bytes. 
  return ~crc;                                                                                                                                                                             // Return the inverted result. 
}


static inline float normalize_yaw_from_filter(float yaw) {
  if (yaw > 180.0f) {
    yaw -= 360.0f;
  }
  return normalize_angle(yaw);
}

static void refresh_orientation_from_filter() {
  device_roll = normalize_angle(orientationFilter.getRoll());
  device_pitch = normalize_angle(orientationFilter.getPitch());
  device_yaw = normalize_yaw_from_filter(orientationFilter.getYaw());
}

void prime_orientation_filter()
{
  orientationFilter = Madgwick();
  orientationFilter.begin(100.0f);

  const unsigned long timeout_ms = 1000;
  unsigned long start = millis();
  unsigned long lastMicrosLocal = 0;
  bool updated = false;

  while (millis() - start < timeout_ms) {
    if (!(IMU.gyroscopeAvailable() && IMU.accelerationAvailable())) {
      delay(5);
      continue;
    }

    float ax, ay, az;
    float gx, gy, gz;
    if (IMU.readGyroscope(gx, gy, gz) == 0) {
      continue;
    }
    if (IMU.readAcceleration(ax, ay, az) == 0) {
      continue;
    }

    float mx = 0.0f, my = 0.0f, mz = 0.0f;
    bool hasMag = IMU.magneticFieldAvailable() && IMU.readMagneticField(mx, my, mz);

    unsigned long nowMicros = micros();
    if (lastMicrosLocal != 0 && nowMicros > lastMicrosLocal) {
      float dt = (nowMicros - lastMicrosLocal) / 1000000.0f;
      if (dt > 0.001f && dt < 0.2f) {
        orientationFilter.begin(1.0f / dt);
      }
    }
    lastMicrosLocal = nowMicros;

    if (hasMag) {
      orientationFilter.update(gx, gy, gz, ax, ay, az, mx, my, mz);
    } else {
      orientationFilter.updateIMU(gx, gy, gz, ax, ay, az);
    }
    updated = true;
  }

  if (!updated) {
    Serial.println("IMU calibration failed: no samples captured");
    device_roll = 0.0f;
    device_pitch = 0.0f;
    device_yaw = 0.0f;
  } else {
    refresh_orientation_from_filter();
  }

  lastOrientationUpdateMicros = micros();
}
void update_info_chracteristic()
{
  BLESystemInfo system_info = {0};
  memcpy(&system_info.version, handx_version, 12 * sizeof(uint8_t));
  memcpy(&system_info.dongle_sn, dongle_SN, 12 * sizeof(char));
  system_info.handx_sn = atoi(handx_SN);

  BLEHeader info_header = {0};
  info_header.rx_tx_code = 0x1B;
  info_header.opcode = OPCODE_INFO;
  info_header.length = 12;
 
  byte send_buf[sizeof(BLESystemInfo) +1];
  memcpy(send_buf, &system_info, sizeof(BLESystemInfo));
  int8_t crc = cala_crc(send_buf, sizeof(BLESystemInfo));
  memcpy(send_buf + sizeof(BLESystemInfo), &crc, sizeof(int8_t));

  byte real_send_buf[sizeof(BLEHeader) + sizeof(BLESystemInfo) +1];
  memcpy(real_send_buf, &info_header, sizeof(BLEHeader));
  memcpy(real_send_buf +sizeof(BLEHeader), send_buf, sizeof(BLESystemInfo) +1);
  if (BLE.connected()) {
    infoCharacteristic.writeValue(real_send_buf, sizeof(BLEHeader) + sizeof(BLESystemInfo) +1);
  }
}


void setup()
{
  Serial1.begin(19200);  //input from RX/TX Pins

  if (!IMU.begin()) {
    Serial.println("Failed to initialize BMI270/BMM150 IMU!");
    while(1) {};
  }

  IMU.setContinuousMode();

  if (!BLE.begin()) {
    Serial.println("Failed to initialize BLE!");
    while(1) {};
  }

  // Prime the fusion output for consistent initial orientation
  prime_orientation_filter();

  String address = BLE.address();
  String name;
  address.toUpperCase();

  name = "HXDongle";
  name += "-";
  name += address[address.length() - 5];
  name += address[address.length() - 4];
  name += address[address.length() - 2];
  name += address[address.length() - 1];

  dongle_SN[0]= address[0];
  dongle_SN[1]= address[1];

  dongle_SN[2]= address[3];
  dongle_SN[3]= address[4];

  dongle_SN[4]= address[6];
  dongle_SN[5]= address[7];

  dongle_SN[6]= address[9];
  dongle_SN[7]= address[10];

  dongle_SN[8]= address[12];
  dongle_SN[9]= address[13];

  dongle_SN[10]= address[15];
  dongle_SN[11]= address[16];

  BLE.setLocalName(name.c_str());
  BLE.setDeviceName(name.c_str());
  BLE.setAdvertisedService(InfoService);

  InfoService.addCharacteristic(FastDataCharacteristic);
  InfoService.addCharacteristic(SlowDataCharacteristic);
  InfoService.addCharacteristic(infoCharacteristic);
  InfoService.addCharacteristic(LEDswitchCharacteristic);
  InfoService.addCharacteristic(InfoRequestCharacteristic);

  BLE.addService(InfoService);
  BLE.advertise();

  // set LED's pin to output mode
  pinMode(LEDR, OUTPUT);
  pinMode(LEDG, OUTPUT);
  pinMode(LEDB, OUTPUT);
 
  digitalWrite(LEDR, LOW);               // will turn the LED off
  digitalWrite(LEDG, LOW);               // will turn the LED off
  digitalWrite(LEDB, LOW);

  // Pin D2: Enable HandX TX output (active LOW).
  pinMode(2, OUTPUT);
  digitalWrite(2, LOW);
}


void operate_LED(uint8_t value)
{
   switch (value)
   {   // any value other than 0
    case 01:
      Serial.println("Red LED on");
      digitalWrite(LEDR, LOW);            // will turn the LED on
      digitalWrite(LEDG, HIGH);         // will turn the LED off
      digitalWrite(LEDB, HIGH);         // will turn the LED off
      break;
    case 02:
      Serial.println("Green LED on");
      digitalWrite(LEDR, HIGH);         // will turn the LED off
      digitalWrite(LEDG, LOW);        // will turn the LED on
      digitalWrite(LEDB, HIGH);        // will turn the LED off
      break;
    case 03:
      Serial.println("Blue LED on");
      digitalWrite(LEDR, HIGH);         // will turn the LED off
      digitalWrite(LEDG, HIGH);       // will turn the LED off
      digitalWrite(LEDB, LOW);         // will turn the LED on
      break;
    case 04:
      Serial.println("Purple LED on");
      digitalWrite(LEDR, LOW);
      digitalWrite(LEDG, HIGH);
      digitalWrite(LEDB, LOW);
      break;
    case 05:
      Serial.println("Turkiz LED on");
      digitalWrite(LEDR, HIGH);
      digitalWrite(LEDG, LOW);
      digitalWrite(LEDB, LOW);
      break;
    case 06:
      Serial.println("Yellow LED on");
      digitalWrite(LEDR, LOW);
      digitalWrite(LEDG, LOW);
      digitalWrite(LEDB, HIGH);
      break;
    case 07:
      Serial.println("White LED on");
      digitalWrite(LEDR, LOW);
      digitalWrite(LEDG, LOW);
      digitalWrite(LEDB, LOW);        
      break;    
    default:
      Serial.println("LEDs off");
      digitalWrite(LEDR, HIGH);
      digitalWrite(LEDG, HIGH);
      digitalWrite(LEDB, HIGH);
      break;
  }
}


// IMU DATA
const int numReadings  = 50;
int readings [numReadings];
int readIndex  = 0;
long total  = 0;
int16_t lastJOYValues[4] = {0};
int8_t  lastFUValues[2]  = {0};
unsigned long lastDebugPrint = 0;

void update_imu_madgwick(){
  bool updated = false;

  while (IMU.gyroscopeAvailable() && IMU.accelerationAvailable()) {
    float ax, ay, az;
    float gx, gy, gz;
    if (IMU.readGyroscope(gx, gy, gz) == 0) {
      continue;
    }
    if (IMU.readAcceleration(ax, ay, az) == 0) {
      continue;
    }

    float mx = 0.0f, my = 0.0f, mz = 0.0f;
    bool hasMag = IMU.magneticFieldAvailable() && IMU.readMagneticField(mx, my, mz);

    unsigned long nowMicros = micros();
    if (lastOrientationUpdateMicros != 0 && nowMicros > lastOrientationUpdateMicros) {
      float dt = (nowMicros - lastOrientationUpdateMicros) / 1000000.0f;
      if (dt > 0.001f && dt < 0.2f) {
        orientationFilter.begin(1.0f / dt);
      }
    }
    lastOrientationUpdateMicros = nowMicros;

    if (hasMag) {
      orientationFilter.update(gx, gy, gz, ax, ay, az, mx, my, mz);
    } else {
      orientationFilter.updateIMU(gx, gy, gz, ax, ay, az);
    }

    refresh_orientation_from_filter();
    updated = true;
  }

  if (!updated && lastOrientationUpdateMicros == 0) {
    lastOrientationUpdateMicros = micros();
  }
}

void maybe_debug_print() {
  if (!Serial) {
    return;
  }

  unsigned long now = millis();
  if (now - lastDebugPrint < 100) {
    return; // limit to 10 Hz
  }
  lastDebugPrint = now;

  Serial.print("IMU r/p/y: ");
  Serial.print(device_roll, 2); Serial.print(", ");
  Serial.print(device_pitch, 2); Serial.print(", ");
  Serial.print(device_yaw, 2);

  Serial.print(" | JOY: ");
  Serial.print(lastJOYValues[0]); Serial.print(", ");
  Serial.print(lastJOYValues[1]); Serial.print(", ");
  Serial.print(lastJOYValues[2]); Serial.print(", ");
  Serial.print(lastJOYValues[3]);

  Serial.print(" | FU: ");
  Serial.print(lastFUValues[0]); Serial.print(", ");
  Serial.println(lastFUValues[1]);
}

uint8_t message_bytes[80];
uint16_t msg_index = 0;
uint8_t prev_serial_byte = 0;
uint32_t led_timeout = 0;

void parse_device_info_msg(uint16_t msg_len, uint16_t opcode )
{
  uint16_t input_opcode = 0;
  memcpy(&input_opcode, &message_bytes[2], sizeof(uint16_t));
  if (input_opcode != opcode) {
    Serial.print("Recive different opcode: ");
    Serial.println(input_opcode);
    return;
  }

  uint16_t input_crc = 0;
  memcpy(&input_crc, &message_bytes[msg_len-2], sizeof(uint16_t));
  
  uint16_t calc_crc = crc16((uint8_t*) &message_bytes[0], msg_len-2);

  static uint32_t crc_fail_info = 0;
  if (calc_crc != input_crc)
  {
    if (++crc_fail_info % 50 == 0) {
      Serial.println("Failed info CRC");
    }
    return;
  }

  //Serial.println("-------Revicved info");
  memcpy(&handx_version, &message_bytes[6], 12 * sizeof(uint8_t));
  memcpy(&handx_SN, &message_bytes[6+12], 8 * sizeof(uint8_t));
}


void parse_real_time_data_msg(uint16_t msg_len, uint16_t opcode )
{
  uint16_t input_opcode = 0;
  memcpy(&input_opcode, &message_bytes[2], sizeof(uint16_t));

  if (input_opcode != opcode) {
    Serial.print("Recive different opcode: ");
    Serial.println(input_opcode);
    return;
  }

  uint16_t input_crc = 0;
  memcpy(&input_crc, &message_bytes[msg_len-2], sizeof(uint16_t));
  uint16_t calc_crc = crc16((uint8_t*) &message_bytes[0], msg_len-2);

  static uint32_t crc_fail_rt = 0;
  if (calc_crc != input_crc) {
   if (++crc_fail_rt % 50 == 0) {
     Serial.println("Failed CRC validation");
   }
   return;
  }

  HandXDeviceData data = { 0 };

  data.seq = packet_seq;
  data.IMUValues[0] = clamp_angle_deg(device_roll);
  data.IMUValues[1] = clamp_angle_deg(device_pitch);
  data.IMUValues[2] = clamp_angle_deg(device_yaw);

  memcpy(&data.RollRange, &message_bytes[6], 25 * sizeof(uint8_t));
  memcpy(lastJOYValues, data.JOYValues, sizeof(lastJOYValues));
  memcpy(lastFUValues,  data.FUValues,  sizeof(lastFUValues));

  maybe_debug_print();

  BLEFastData fast = {0};
  fast.seq = packet_seq;
  memcpy(fast.IMUValues, data.IMUValues, sizeof(int16_t) * 3);
  memcpy(fast.JOYValues, data.JOYValues, sizeof(int16_t) * 4);
  fast.FUValues[0] = data.FUValues[0];
  fast.FUValues[1] = data.FUValues[1];

  BLESlowData slow = {0};
  slow.seq = packet_seq;
  slow.RollRange = data.RollRange;
  slow.SysState      = data.SysState;
  slow.LockState     = data.LockState;
  slow.CouplingState = data.CouplingState;
  slow.InvertMode    = data.InvertMode;
  memcpy(slow.ButtonEvent,       data.ButtonEvent,       3);
  memcpy(slow.ButtonNumberEvents,data.ButtonNumberEvents,3);
  memcpy(slow.ButtonState,       data.ButtonState,       3);

  byte send_buf[sizeof(BLESlowData) + 1];
  memcpy(send_buf, &slow, sizeof(BLESlowData));

  int8_t crc = cala_crc(send_buf, sizeof(BLESlowData));
  memcpy(send_buf + sizeof(BLESlowData), &crc, sizeof(int8_t));

  BLEHeader data_header = {0};
  data_header.rx_tx_code = 0x1B;
  data_header.opcode = OPCODE_REALTIME;
  data_header.length = sizeof(BLESlowData);

  byte real_send_buf[sizeof(BLEHeader) + sizeof(BLESlowData) + 1];
  memcpy(real_send_buf, &data_header, sizeof(BLEHeader));
  memcpy(real_send_buf + sizeof(BLEHeader), send_buf, sizeof(BLESlowData) + 1);

  unsigned long now = millis();
  if (now - lastFastSend >= FAST_BLE_INTERVAL_MS) {
    if (BLE.connected()) {
      FastDataCharacteristic.writeValue((byte*)&fast, sizeof(BLEFastData));
    }
    lastFastSend = now;
    packet_seq++;
  }
  if (now - lastSlowSend >= SLOW_BLE_INTERVAL_MS) {
    if (BLE.connected()) {
      SlowDataCharacteristic.writeValue(real_send_buf, sizeof(BLEHeader) + sizeof(BLESlowData) + 1);
    }
    lastSlowSend = now;
  }
}

void parse_msg(uint16_t msg_len)
{
  // message bytes exclude start/stop flags
  if (msg_len < 4) {
    return; // not enough data for opcode
  }

  uint16_t opcode = 0;
  memcpy(&opcode, &message_bytes[2], sizeof(uint16_t));

  switch (opcode) {
    case 2754: // real-time data
      parse_real_time_data_msg(msg_len, opcode);
      break;
    case 2755: // device info
      parse_device_info_msg(msg_len, opcode);
      break;
    default:
      Serial.print("Unknown opcode: ");
      Serial.println(opcode);
      break;
  }
}

void process_serial_stream() {
  static bool escape_next = false;
  while (Serial1.available()) {
    uint8_t b = Serial1.read();

    if (escape_next) {
      b ^= 0x20; // unescape
      escape_next = false;
      if (msg_index < sizeof(message_bytes)) {
        message_bytes[msg_index++] = b;
      }
      prev_serial_byte = b;
      continue;
    }

    if (b == ESC_BYTE) {
      escape_next = true;
      prev_serial_byte = b;
      continue;
    }

    if (is_start_byte(b, prev_serial_byte)) {
      msg_index = 0;
    } else if (is_stop_byte(b, prev_serial_byte) && msg_index > 0) {
      parse_msg(msg_index);
      msg_index = 0;
    } else if (msg_index < sizeof(message_bytes)) {
      message_bytes[msg_index++] = b;
    }

    prev_serial_byte = b;
  }
}

void loop()
{
  update_imu_madgwick();
  process_serial_stream();

  if (LEDswitchCharacteristic.written()) {
    uint8_t led_value = LEDswitchCharacteristic.value();
    if (led_value) {
      Serial.println("Receive LED command");
      operate_LED(led_value);
      led_timeout = 1;
    }
  }

  if (led_timeout > 0) {
    if (++led_timeout > 5000) {
      operate_LED(7);
      led_timeout = 0;
    }
  }

  if (InfoRequestCharacteristic.written()) {
    Serial.println("Got Info request");
    if (InfoRequestCharacteristic.value()) {
      Serial.println("Senfing Info data");
      update_info_chracteristic();
    }
  }

    // Free-running loop — IMU updates at its native rate
}
