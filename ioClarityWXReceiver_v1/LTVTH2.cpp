#include "LTVTH2.h"

void LTVTH2::DecodeFrame(byte *bytes, struct LTVTH2::Frame *frame) {

  // * D = Device ID (bytes 0, 1, 2)
  // * S = Sequence (3 bit Counter)
  // * N = New Battery Flag   (I think)
  // * T = (Temprature * 10) + 40
  // * W = Weak Battery Flag  (I  think)
  // * H = Humidity 
  // * X = Checksum
  // * Z = Trailer (D2 D2 D2 D2 D2)
  //
  //  Byte0    Byte1    Byte2   Byte3     Byte4   Byte5     Byte6    Byte7    Byte8    Byte9    Byte10   Byte11   Byte12
  // DDDDDDDD DDDDDDDD DDDDDDDD ____SSSN TTTTTTTT TTTT____ WHHHHHHH XXXXXXXX ZZZZZZZZ ZZZZZZZZ ZZZZZZZZ ZZZZZZZZ ZZZZZZZZ        
  // 00110101 10011000 11100000 00000000 00000111 10010000 00111011 01101000 11010010 11010010 11010010 11010010 11010010
  
  frame->IsValid = true;
  frame->CRC = bytes[7];

  frame->Sequence = (bytes[3] >> 1) & 0x07;

  // For now do not validate CRC
  //
  //uint8_t chk1 = crc8(bytes, 8, 0x31, 0x00);
  // Sequence 2 & 6, CHK1 == 0
  // Sequence 0,1,3,4,5 & 7 CHK1 == 0xAC
  //if ( frame->Sequence == 2 || frame->Sequence == 6 ) {
  //  if( chk1 != 0x00 )
  //  { frame->IsValid = false; }
  //} else {
  // if( chk1 != 0xAC )
  // { frame->IsValid = false; }
  //}


  //Ensure Trailer is 5 D2's starting at the 9th byte.
  if( (bytes[8] != 0xD2)  || (bytes[9] != 0xD2)  || 
      (bytes[10] != 0xD2) || (bytes[11] != 0xD2) ||
      (bytes[12] != 0xD2) )
      { frame->IsValid = false; }
  
  //ID is first three bytes
  frame->ID[0] = bytes[0];
  frame->ID[1] = bytes[1];
  frame->ID[2] = bytes[2];

  // extract the temperature.
  // IT is stored as the number of tenth degrees above -40 C
  float t = bytes[4] * 16;
  t += ((bytes[5] & 0xF0) >> 4 );
  t =  t / 10;
  t -= 40;
  
  frame->Temperature = t;
  frame->Humidity = (bytes[6] & 0x7F);                   // Mask off the first bit
  frame->WeakBatteryFlag = (bytes[6] & 0x80) >> 7;       // Not 100% sure on this is actually weak batt
  frame->NewBatteryFlag  = (bytes[3] & 0x01);            // Not 100% sure on this is new batt flag
}

// Function to get the data string from a passed dataframe
String LTVTH2::GetDataString(byte *data) {
  String dataString = "";

  struct LTVTH2::Frame frame;
  DecodeFrame(data, &frame);               //decode data and put in the frame
  if (frame.IsValid) {
    dataString = BuildDataString(&frame);  //if it is a valid dataframe, then build 
  }
  
  return dataString;
}

// Function to try handling this data
bool LTVTH2::TryHandleData(byte *data) {
  String dataString = GetDataString(data);

  if (dataString.length() > 0) {
    Serial.println(dataString);
  }
  return dataString.length() > 0;
}


String LTVTH2::BuildDataString(struct LTVTH2::Frame *frame) {
  // Fixed output - roughly based on the FHEM format.
  // 
  // OK  LTVTH2  3598E0 1     4 240  65   0   0 0 0 0    1st in sequence -- +26.4C -- 65% humidity
  // OK  LTVTH2  3598E0 5     3  50  80   0   1 0 0 0    5th in sequence -- -18.2C -- 80% humidity -- weak battery
  // OK  LTVTH2  DDDDDD SEQ TTT TTT  HH   N   W X X X
  //     |        |     |    |   |    |   |   | \\\\\\  Flags for future use, for now always 0
  //     |        |     |    |   |    |   |   |  
  //     |        |     |    |   |    |   |    `- Weak Battery Flag (1 placeholder)
  //     |        |     |    |   |    |    `--- New Battery Flag (1 placeholder)
  //     |        |     |    |   |     `------ Humidity (1-2 placeholders)
  //     |        |     |    |   |   
  //     |        |     |    |    `------ Temp * 10 + 1000 LSB (1-3 placeholders)
  //     |        |     |    `----------- Temp * 10 + 1000 MSB (1-3 placeholders)
  //     |        |      `---Sequence (0-7) (1 placeholder)
  //     |        |    
  //     |         `------- ID (3 placeholders)
  //      `--- fix "LTVTH2"

  //  ID
  String result;
  result += "OK LTVTH2 ";
  result += String(frame->ID[0], HEX);
  result += String(frame->ID[1], HEX);
  result += String(frame->ID[2], HEX);
  result += " ";

  // add Sequence
  result += (uint8_t)frame->Sequence;
  result += " ";
  
  // add temperature
  uint16_t tempTemp = (uint16_t)(frame->Temperature * 10 + 1000);
  result += (byte)(tempTemp >> 8);
  result += ' ';
  result += (byte)(tempTemp);
  result += ' ';

  // add humidity
  result += frame->Humidity;
  result += ' ';

  // add weak battery flag
  result += frame->WeakBatteryFlag;
  result += " ";
  
  // add new battery flag
  result += frame->NewBatteryFlag;
  result += " ";

  result += "0 0 0"; //flags for future use
  return result;
}

// Function to print out the details of a LTVTH2 frame
String LTVTH2::AnalyzeFrame(byte *data) {
  String result;
  struct LTVTH2::Frame frame;
  DecodeFrame(data, &frame);
  // Show the raw data bytes
  result += "LTVTH2 [";
  for (int i = 0; i < FRAME_LENGTH; i++) {
    result += String(data[i], HEX);
    result += " ";
  }
  result += "]";

  // Check valid flag
  if (!frame.IsValid) {
    result += " Valid: No";
  }
  else {
    result += " Valid: Yes";
  }
 
  // ID
  result += " ID: ";
  result += String(frame.ID[0], HEX);
  result += String(frame.ID[1], HEX);
  result += String(frame.ID[2], HEX);

  // Seq
  result += " SEQ: ";
  result += String(frame.Sequence, DEC);
  
  // Temp
  result += " T: ";
  result += String(frame.Temperature);

  // Humidity
  result += " H: ";
  result += String(frame.Humidity);

  // WeakBatteryFlag
  result += " WB: ";
  result += String(frame.WeakBatteryFlag, BIN);

  // New Battery Flag
  result += " NB: ";
  result += String(frame.NewBatteryFlag, BIN);

  // CRC
  result += " CRC: ";
  result += String(frame.CRC, HEX);

  return result;
}

// Future use - going to be used to verify data frame using the CRC frame
uint8_t LTVTH2::crc8(uint8_t const message[], unsigned nBytes, uint8_t polynomial, uint8_t init)
{
    uint8_t remainder = init;
    unsigned byte, bit;

    for (byte = 0; byte < nBytes; ++byte) {
        remainder ^= message[byte];
        for (bit = 0; bit < 8; ++bit) {
            if (remainder & 0x80) {
                remainder = (remainder << 1) ^ polynomial;
            } else {
                remainder = (remainder << 1);
            }
        }
    }
    return remainder;
}

// LTVTH2 datarate is 9600
bool LTVTH2::IsValidDataRate(unsigned long dataRate) {
  return dataRate == 9600ul;
}
