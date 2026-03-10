#include <Arduino.h>
#define STEP_PIN PA0
#define DIR_PIN  PA1
#define EN_PIN   PA2

#define SERIAL_BT Serial1

const int STEPS_PER_REV = 4096;      // GM12-15BY
const float STEP_ANGLE = 360.0 / STEPS_PER_REV;

const float TARGET_INCREMENT = 180.0; // cada click
const int TOTAL_STAGES = 24;

const int MAX_STEP_RATE = 8000;      // pasos/seg
const int MIN_STEP_RATE = 10;

float Kp = 18.0;
float Ki = 0.02;
float Kd = 3.0;

float pid_integral = 0;
float pid_last_error = 0;

volatile long current_steps = 0;
volatile long target_steps = 0;

unsigned long last_step_time = 0;
unsigned long step_interval = 1000;

void stepMotor()
{
    digitalWrite(STEP_PIN, HIGH);
    delayMicroseconds(2);
    digitalWrite(STEP_PIN, LOW);
}

void setDirection(bool dir)
{
    digitalWrite(DIR_PIN, dir);
}

void enableMotor(bool en)
{
    digitalWrite(EN_PIN, !en);
}

float computePID(float error)
{
    pid_integral += error;

    float derivative = error - pid_last_error;

    float output =
        (Kp * error) +
        (Ki * pid_integral) +
        (Kd * derivative);

    pid_last_error = error;

    return output;
}

void motorControl()
{
    long error_steps = target_steps - current_steps;

    if (error_steps == 0)
        return;

    float error_deg = error_steps * STEP_ANGLE;

    float pid = computePID(error_deg);

    int rate = abs(pid);

    if (rate > MAX_STEP_RATE) rate = MAX_STEP_RATE;
    if (rate < MIN_STEP_RATE) rate = MIN_STEP_RATE;

    step_interval = 1000000 / rate;

    bool dir = error_steps > 0;

    setDirection(dir);

    unsigned long now = micros();

    if (now - last_step_time >= step_interval)
    {
        last_step_time = now;

        stepMotor();

        if (dir)
            current_steps++;
        else
            current_steps--;
    }
}

void moveStages(int stages)
{
    long move_steps =
        (TARGET_INCREMENT / STEP_ANGLE) * stages;

    target_steps += move_steps;
}

void parseCommand(char c)
{
    switch (c)
    {

    case 'A': moveStages(1); break;
    case 'B': moveStages(-1); break;

    case 'C': moveStages(2); break;
    case 'D': moveStages(-2); break;

    case 'E': moveStages(6); break;
    case 'F': moveStages(-6); break;

    case 'G':
        current_steps = 0;
        target_steps = 0;
        break;

    case 'P': Kp += 1.0; break;
    case 'p': Kp -= 1.0; break;

    case 'I': Ki += 0.005; break;
    case 'i': Ki -= 0.005; break;

    case 'D': Kd += 0.5; break;
    case 'd': Kd -= 0.5; break;

    }
}
void setup()
{
    pinMode(STEP_PIN, OUTPUT);
    pinMode(DIR_PIN, OUTPUT);
    pinMode(EN_PIN, OUTPUT);

    enableMotor(true);

    SERIAL_BT.begin(115200);
}

void loop()
{
    while (SERIAL_BT.available())
    {
        char cmd = SERIAL_BT.read();
        parseCommand(cmd);
    }

    motorControl();
}