#ifndef _LTVTH2_h
#define _LTVTH2_h

#include "Arduino.h"
#include "SensorBase.h"

class LTVTH2 : public SensorBase {
public: 
  struct Frame {
    byte  ID[3];
    byte  Sequence;
    byte  CRC;
    float Temperature;
    byte  Humidity;
    bool  NewBatteryFlag;
    bool  WeakBatteryFlag;
    bool  IsValid;
  };
  
  static const byte FRAME_LENGTH = 7;

  static void DecodeFrame(byte *bytes, struct LTVTH2::Frame *frame);
  static bool TryHandleData(byte *data);
  static String GetDataString(byte *data);
  static bool IsValidDataRate(unsigned long dataRate);
  static String AnalyzeFrame(byte *data);

protected:
  static String BuildDataString(struct LTVTH2::Frame *frame);
  static uint8_t crc8(uint8_t const message[], unsigned nBytes, uint8_t polynomial, uint8_t init);
};

#endif
