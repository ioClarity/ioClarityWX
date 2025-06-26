#ifndef _SENSORBASE_h
#define _SENSORBASE_h

#include "Arduino.h"

class SensorBase {
public: 
  struct Frame {
    byte  ID[3];
    byte  CRC;
    bool  IsValid;
    byte  Data[128];
    byte  NbrOfDataBytes;
  };
  static void SetDebugMode(boolean mode);
  static byte GetFrameLength(byte data[]);
  static String AnalyzeFrame(byte *data);
  static bool TryHandleData(byte *data);
  static String GetFhemDataString(byte *data);
  static bool IsValidDataRate(unsigned long dataRate);

protected:
  static bool m_debug;
  unsigned long m_dataRate;
 
};

#endif
