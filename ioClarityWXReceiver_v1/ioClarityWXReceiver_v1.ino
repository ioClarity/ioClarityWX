// This JeeLink sketch is heavly based ont he FHEM sketch for receiving LaCrosse data.  It has been stripped down
// and modified for my little project which is to receive data for a particular setup consisting of:
//
//    * LTV-TH2   (Temp/Humidity Sensor)
//    * LTV-W1    (Wind Sensor)
//    * LTV-R2    (Rain Sensor)
//
// All of these devices are on the 915 MhZ band, using 9600 baud.
//
//     Contact:  robert@ioclarity.ca
//
// Changelog: 2021-02-07   * Initial Creation
//                         * Created LTVTH2 Sensor.
//
#define PROGNAME         "ioClarityWXReceiver"
#define PROGVERS         "v1"   

#include "RFM.h"
#include "SensorBase.h"
#include "JeeLink.h"
#include <Wire.h>
#include "LTVTH2.h"

// --- Configuration ---------------------------------------------------------------------------------------------------

#define ENABLE_ACTIVITY_LED    1         // <n>a     set to 0 if the blue LED bothers
bool DEBUG                   = 0;        // <n>d     set to 1 to see debug messages
unsigned long INITIAL_FREQ   = 915000;   //  Fixs frequency at 915Mhz
unsigned long DATA_RATE_R1   = 9600ul;   //  Fixs Baud at 9600
                                         // v        show version
bool ANALYZE_FRAMES         = 0;         // <n>z     set to 1 to display analyzed frame data instead of the normal data


// --- Variables -------------------------------------------------------------------------------------------------------
byte commandData[32];
byte commandDataPointer = 0;

RFM rfm1(11, 12, 13, 10);
JeeLink jeeLink;

// Function to handle input coming from the serial port
// accepts commands like "0a" (disables blue LED)
static void HandleSerialPort(char c) {
  static unsigned long value;
  unsigned long dataRate = 0;

  if (c == ',') {
    commandData[commandDataPointer++] = value;
    value = 0;
  }
  else if ('0' <= c && c <= '9') {
    value = 10 * value + c - '0';
  }
  else if (('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')) {
    switch (c) {
    case 'd':
      // DEBUG
      SetDebugMode(value);
      break;

    case 'a':
      // Activity LED    
      jeeLink.EnableLED(value);
      break;

    case 'v':
      // Version info
      HandleCommandV();
      break;

    case 'z':
      ANALYZE_FRAMES = value;
      break;

    default:
      HandleCommandV();
      break;
    }
    value = 0;
  }
  else if (' ' < c && c < 'A') {
    HandleCommandV();
  }
}

// Function to enable Debugging mode
void SetDebugMode(boolean mode) {
  DEBUG = mode;
  rfm1.SetDebugMode(mode);
}


// Function to printout version information
void HandleCommandV() {
  Serial.print("\n[");
  Serial.print(PROGNAME);
  Serial.print('.');
  Serial.print(PROGVERS);
  Serial.print(" (");
  Serial.print(rfm1.GetRadioName());
  Serial.print(" f:");
  Serial.print(rfm1.GetFrequency());
  Serial.print(" r:");
  Serial.print(rfm1.GetDataRate());
  Serial.print(")");
  Serial.println(']');
}

// Function to handle data that is received over RF
void HandleReceivedData(RFM *rfm) {
  rfm->EnableReceiver(false);  //disable while we process

  byte payload[PAYLOADSIZE];
  rfm->GetPayload(payload);

  // if ANALYZE Frames is enabled, print out the details, otherwise proccess it
  if (ANALYZE_FRAMES) {
    Serial.println( LTVTH2::AnalyzeFrame(payload) );
  }
  else {
    //Blinky
    jeeLink.Blink(1);

    //If debug is enabled, print out the details
    if (DEBUG) {
      Serial.print("\nEnd receiving, HEX raw data: ");
      for (int i = 0; i < 16; i++) {
        Serial.print(payload[i], HEX);
        Serial.print(" ");
      }
      Serial.println();
    }

    byte frameLength = 0;

    // Try LTVTH2
    if (LTVTH2::IsValidDataRate(rfm->GetDataRate()) && LTVTH2::TryHandleData(payload)) {
      frameLength = LTVTH2::FRAME_LENGTH;
    }
    
  }
  rfm->EnableReceiver(true);  //re-enable now that we are done
}

// ********** MAIN PROGRAM LOOP **********************
void loop(void) {
  // Handle the commands from the serial port
  // ----------------------------------------
  if (Serial.available()) {
    HandleSerialPort(Serial.read());
  }

  // Handle the data reception
  // -------------------------
    rfm1.Receive();
    if (rfm1.PayloadIsReady()) {
      HandleReceivedData(&rfm1);
    }      
}

// ********** ONE TIME SETUP ********************
void setup(void) {
  //set Baud Rate
  Serial.begin(57600);
  delay(200);
 
  SetDebugMode(DEBUG);
  
  Wire.begin();
  jeeLink.EnableLED(ENABLE_ACTIVITY_LED);

  rfm1.Begin(true);
  rfm1.InitializeLaCrosse();
  rfm1.SetFrequency(INITIAL_FREQ);
  rfm1.SetDataRate(DATA_RATE_R1);
  rfm1.EnableReceiver(true); 
  
  if (DEBUG) {
    Serial.println("Radio setup complete. Starting to receive messages");
  }

  delay(1000);
  HandleCommandV();
}
