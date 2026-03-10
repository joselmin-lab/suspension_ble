#include <Arduino.h>

// ===== BLE UART =====
#define SERIAL_BT Serial1
static const uint32_t BAUD = 115200;

// ===== Motors pins (STEP, DIR, EN) =====
// M1 // PA0, PA1, PA2
// M2 // PA3, PA4, PA5
// M3 // PA6, PA7, PB0   (ojo: comentario original tenía typo "PA7M PB0")
// M4 // PB1, PB10, PB11
static const uint8_t STEP_PIN[4] = {PA0, PA3, PA6, PB1};
static const uint8_t DIR_PIN[4]  = {PA1, PA4, PA7, PB10};
static const uint8_t EN_PIN[4]   = {PA2, PA5, PB0, PB11};

// enableMotor(true) => habilitado (EN activo en LOW como en tu código original)
static inline void enableMotor(int i, bool en) { digitalWrite(EN_PIN[i], !en); }
static inline void setDirection(int i, bool dir) { digitalWrite(DIR_PIN[i], dir); }
static inline void stepMotor(int i) {
  digitalWrite(STEP_PIN[i], HIGH);
  delayMicroseconds(2);
  digitalWrite(STEP_PIN[i], LOW);
}

// ===== Motor + PID params =====
static const int STEPS_PER_REV = 4096;      // GM12-15BY (según tu código)
static const float STEP_ANGLE = 360.0f / (float)STEPS_PER_REV;

// En tu firmware: 180° por "click"
static const float CLICK_DEG = 180.0f;
static const int MIN_CLICKS = 0;
static const int MAX_CLICKS = 22;

// Rango velocidad (pasos por segundo)
static const int MAX_STEP_RATE = 8000;
static const int MIN_STEP_RATE = 10;

// PID (por motor)
float Kp = 18.0f;
float Ki = 0.02f;
float Kd = 3.0f;

float pid_integral[4] = {0, 0, 0, 0};
float pid_last_error[4] = {0, 0, 0, 0};

// Estado (por motor)
volatile long current_steps[4] = {0, 0, 0, 0};
volatile long target_steps[4]  = {0, 0, 0, 0};

int current_clicks[4] = {0, 0, 0, 0};
int target_clicks[4]  = {0, 0, 0, 0};

// Timing stepping
uint32_t last_step_us[4] = {0, 0, 0, 0};
uint32_t step_interval_us[4] = {1000, 1000, 1000, 1000};

// ===== Helpers =====
static inline int clampClicks(int v) {
  if (v < MIN_CLICKS) return MIN_CLICKS;
  if (v > MAX_CLICKS) return MAX_CLICKS;
  return v;
}

static inline long clicksToSteps(int clicks) {
  // steps_per_click = CLICK_DEG / STEP_ANGLE
  const float stepsPerClick = CLICK_DEG / STEP_ANGLE;
  return (long)(stepsPerClick * (float)clicks);
}

static float computePID(int i, float error_deg) {
  pid_integral[i] += error_deg;
  const float derivative = error_deg - pid_last_error[i];

  const float output = (Kp * error_deg) + (Ki * pid_integral[i]) + (Kd * derivative);
  pid_last_error[i] = error_deg;
  return output;
}

static void setTargetClicks(int motorIndex0, int clicks) {
  clicks = clampClicks(clicks);
  target_clicks[motorIndex0] = clicks;
  target_steps[motorIndex0] = clicksToSteps(clicks);
}

static void resetMotorState(int i) {
  current_steps[i] = 0;
  target_steps[i] = 0;
  current_clicks[i] = 0;
  target_clicks[i] = 0;
  pid_integral[i] = 0;
  pid_last_error[i] = 0;
}

static void sendStatus() {
  // Ej: S:FL=0,FR=0,RL=0,RR=0,PID=18,0.02,3
  SERIAL_BT.print("S:");
  SERIAL_BT.print("M1="); SERIAL_BT.print(target_clicks[0]);
  SERIAL_BT.print(",M2="); SERIAL_BT.print(target_clicks[1]);
  SERIAL_BT.print(",M3="); SERIAL_BT.print(target_clicks[2]);
  SERIAL_BT.print(",M4="); SERIAL_BT.print(target_clicks[3]);
  SERIAL_BT.print(",PID=");
  SERIAL_BT.print(Kp, 3); SERIAL_BT.print(",");
  SERIAL_BT.print(Ki, 5); SERIAL_BT.print(",");
  SERIAL_BT.print(Kd, 3);
  SERIAL_BT.print("\n");
}

// ===== Control loop per motor =====
static void motorControlTick(int i) {
  const long error_steps = target_steps[i] - current_steps[i];
  if (error_steps == 0) {
    // Si estamos en target, también actualizamos current_clicks para reportar coherente
    current_clicks[i] = target_clicks[i];
    return;
  }

  const float error_deg = (float)error_steps * STEP_ANGLE;
  const float pid = computePID(i, error_deg);

  int rate = abs((int)pid);
  if (rate > MAX_STEP_RATE) rate = MAX_STEP_RATE;
  if (rate < MIN_STEP_RATE) rate = MIN_STEP_RATE;

  step_interval_us[i] = (uint32_t)(1000000UL / (uint32_t)rate);

  const bool dir = (error_steps > 0);
  setDirection(i, dir);

  const uint32_t now = micros();
  if ((uint32_t)(now - last_step_us[i]) >= step_interval_us[i]) {
    last_step_us[i] = now;
    stepMotor(i);
    current_steps[i] += dir ? 1 : -1;
  }
}

// ===== Line parser =====
static char lineBuf[96];
static uint8_t lineLen = 0;

static void handleLine(const char* line) {
  // quitamos espacios
  while (*line == ' ' || *line == '\t' || *line == '\r') line++;
  if (*line == 0) return;

  // GET
  if (strcmp(line, "GET") == 0) {
    sendStatus();
    return;
  }

  // ZERO / RESET
  if (strcmp(line, "ZERO") == 0) {
    for (int i = 0; i < 4; i++) resetMotorState(i);
    SERIAL_BT.print("OK:ZERO\n");
    return;
  }

  // Mx:clicks  (1..4)
  // Ej: M1:10
  if (line[0] == 'M' && line[1] >= '1' && line[1] <= '4' && line[2] == ':') {
    const int motor = (line[1] - '1'); // 0..3
    const int clicksVal = atoi(line + 3);
    setTargetClicks(motor, clicksVal);
    SERIAL_BT.print("OK:M");
    SERIAL_BT.print(motor + 1);
    SERIAL_BT.print("=");
    SERIAL_BT.print(target_clicks[motor]);
    SERIAL_BT.print("\n");
    return;
  }

  // PID:KP=18,KI=0.02,KD=3
  if (strncmp(line, "PID:", 4) == 0) {
    // parse manual simple
    // buscamos KP=, KI=, KD=
    const char* kpPos = strstr(line, "KP=");
    const char* kiPos = strstr(line, "KI=");
    const char* kdPos = strstr(line, "KD=");
    if (!kpPos || !kiPos || !kdPos) {
      SERIAL_BT.print("ERR:PID_FORMAT\n");
      return;
    }

    const float newKp = atof(kpPos + 3);
    const float newKi = atof(kiPos + 3);
    const float newKd = atof(kdPos + 3);

    Kp = newKp;
    Ki = newKi;
    Kd = newKd;

    // (recomendado) reset integral/derivada al cambiar parámetros
    for (int i = 0; i < 4; i++) {
      pid_integral[i] = 0;
      pid_last_error[i] = 0;
    }

    SERIAL_BT.print("OK:PID\n");
    return;
  }

  SERIAL_BT.print("ERR:UNKNOWN\n");
}

static void serialReadLines() {
  while (SERIAL_BT.available()) {
    const char ch = (char)SERIAL_BT.read();

    if (ch == '\n') {
      lineBuf[lineLen] = 0;
      handleLine(lineBuf);
      lineLen = 0;
      continue;
    }

    // ignoramos CR
    if (ch == '\r') continue;

    if (lineLen < sizeof(lineBuf) - 1) {
      lineBuf[lineLen++] = ch;
    } else {
      // overflow -> reset
      lineLen = 0;
      SERIAL_BT.print("ERR:LINE_TOO_LONG\n");
    }
  }
}

void setup() {
  for (int i = 0; i < 4; i++) {
    pinMode(STEP_PIN[i], OUTPUT);
    pinMode(DIR_PIN[i], OUTPUT);
    pinMode(EN_PIN[i], OUTPUT);
    enableMotor(i, true);
  }

  SERIAL_BT.begin(BAUD);
  SERIAL_BT.print("BOOT:STM32_4M\n");

  // Inicialmente target = 0
  for (int i = 0; i < 4; i++) {
    setTargetClicks(i, 0);
  }
}

void loop() {
  serialReadLines();

  // control tick de los 4 motores
  for (int i = 0; i < 4; i++) {
    motorControlTick(i);
  }
}