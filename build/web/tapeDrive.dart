/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

class EventManager {
  Map<String, List<Function>> eventListeners = new Map();

  void listen(eventtype, func) {
    if (eventListeners[eventtype]==null) {
      eventListeners[eventtype] = new List<Function>();
    }
    eventListeners[eventtype].add(func);
  }

  void event(event) {
    if (eventListeners[event.type]!=null) {
      eventListeners[event.type].forEach((eventListener) => eventListener(event));
    }
  }
}

class EventTape {
  String type;
  bool rewind;
  List<int> data;
  
  EventTape(this.type, this.rewind, [this.data]);
  
  EventTape.createEjectEvent() : this("EventTape", false);
  EventTape.createInsertEvent(List<int> data) : this("EventTape", false, data);
  EventTape.createRewindEvent() : this("EventTape", true);
}

class EOFException {
  String message;
  EOFException([this.message]) {
    print("EOFException ${message}");
  }
}

class InvalidFormatException {
  String message;
  InvalidFormatException(this.message) {
    print("InvalidFormatException ${message}");
  }
}

class TapeDrive {

  Config config;
  EventManager eventManager;
  
  TapeDrive(this.config, this.eventManager) {
    eventManager.listen("EventTape", handleEvent);
  }
  
  // ============================================================
  // Attributes
  // ============================================================

  /**
   * Tape peripheral.
   */
  var tapeDatasource = null;

  bool isTapeLoaded() {
    return tapeDatasource!=null;
  }
  
  /**
   * Used for generating pulses from the Tape peripheral.
   */
  int pulseClock = 0;

  /**
   * Width of pulse to be generating.
   */
  int pulseWidth = 0;

  /**
   * State of Tape drive motor.
   */
  bool tapeDriveMotor = false;

  // ============================================================
  // Methods
  // ============================================================

  /**
   * Trigger the state of the tape drive motor.
   * 
   * @param isTapeMotorGoing
   *            <code>true</code> if tape drive motor is going, else
   *            <code>false</code> .
   */
  void triggerTapeMotor(bool isTapeMotorGoing) {
    tapeDriveMotor = isTapeMotorGoing;
    print("Tape drive motor ${isTapeMotorGoing ? "on" : "off"}");
  }

  /**
   * Read a bit from the tape drive. Note tape is expected to be playing, it
   * is not checked here.
   * 
   * @return bit from tape drive.
   */
  bool readTapeBit() {
    if (tapeDatasource != null && tapeDriveMotor) {
      if (++pulseClock > pulseWidth) {

        try {
          pulseWidth = tapeDatasource.nextPulseWidth();
        } catch (e) {
          if (e is EOFException) {
            pulseWidth = -1;
          }
          else {
            throw e;
          }
        }
        if (pulseWidth == -1) {
          print("Tape end");
          // TODO how?
          config.tapePlay = false;
          return true;
        }
        pulseClock = 0;
      }

      return pulseClock < (pulseWidth >> 1);
    }

    return true;
  }

  // ============================================================
  // IEventListener implementation
  // ============================================================\

  /**
   * Handle a insert tape event.
   */
  //@Override
  void handleEvent(EventTape event) {
    if (event.rewind) {
      print("rewind tape");
      tapeDatasource.rewind();
    } else if (event.data == null) {
      tapeDatasource = null;
      print("eject tape");
    } else {
      try {
        print("load tape");
        tapeDatasource = new TapFile(event.data);
      } catch (e) {
        if (e is InvalidFormatException) {
          // Wasn't a TAP file, try CSM
          tapeDatasource = new CsmFile(config, event.data); 
        } else {
          throw e;
        }
      }
    }
  }
}

class PulseWidthsFromBitData {

  Config config;
  TapeBitDataStream bitData;
  
  PulseWidthsFromBitData(this.config, this.bitData) {
    reset();
  }
  
  // ============================================================
  // Attributes
  // ============================================================

  /**
   * Last bit sent.
   */
  bool bit = false;
  
  /**
   * Count of bits sent within datum.
   */
  int count = 0;

  // ============================================================
  // Methods
  // ============================================================

  /**
   * Resets 
   */
  void reset() {
    count = 1;
  }

  // ============================================================
  // IPulseData implementation
  // ============================================================

  /**
   * {@inheritDoc}
   */
  //@Override
  int nextPulseWidth() {
    if (--count == 0) {
      count = 20;
      return config.L; // More data bit 1
    }
    if (count == 19) {
      // More data bit 2
      return bitData.hasNextBit() ? config.M : config.S;
    }
    bit = ((count & 1) != 0) ? !bit : bitData.nextBit();

    return bit ? config.M : config.S;
  }
}


class PulseWidthSyncGenerator {

  // ============================================================
  // Attributes
  // ============================================================

  /**
   * Current sync number being sent.
   */
  int value = 0;

  /**
   * Count of bits sent.
   */
  int count = 0;

  /**
   * Last bit sent.
   */
  bool bit = false;

  /**
   * XOR bit for each datum.
   */
  int xor = 0;
  
  Config config;
  
  PulseWidthSyncGenerator(this.config);
  
  // ============================================================
  // Methods
  // ============================================================

  /**
   * Reset the pulse width generator
   * 
   * @param isRepeat
   *            <code>true</code> if this is the repeat sync pulse, else
   *            <code>false</code>.
   */
  void reset(bool isRepeat) {
    // Repeat syncs start at a different number
    value = isRepeat ? 0x0A : 0x8A;
    count = 0;
  }
  
  // ============================================================
  // IPulseData implementation
  // ============================================================

  /**
   * {@inheritDoc}
   */
  // @Override
  int nextPulseWidth() {
    if (--count < 0) {
      // value is 0x00 or 0x80 then end of sync
      --value;
      if ((value & 0xF) == 0) {
        throw new EOFException();
      }
      count = 19;
      xor = 1;
      // More data pulse 1
      return config.L;
    }
    if (count == 18) {
      // More data pulse 2
      return config.M;
    }
    if (count < 1) {
      // checksum bit
      return ((xor ^ count) != 0) ? config.S : config.M;
    }

    // Get next bit
    if ((count & 1) != 0) {
      bit = ((value >> (8 - (count >> 1))) & 1) != 0;
      xor ^= bit ? 1 : 0;
    }
    // invert current bit
    else {
      bit = !bit;
    }

    return bit ? config.M : config.S;
  }
}

class TapeBitDataStream {

  // ============================================================
  // Attributes
  // ============================================================

  List<int> data = null;
  int offset = 0;

  /**
   * Current byte of data being worked on.
   */
  int datum = 0;

  /**
   * Current checksum for datum.
   */
  int xor = 0;

  /**
   * Current checksum for all data.
   */
  int xorbyte = 0;

  /**
   * Current bit position in datum.
   */
  int bitpos = 0;

  /**
   * <code>true</code> if end of stream checksum has been added.
   */
  bool hasAddedByteChecksum = false;

  // ============================================================
  // Methods
  // ============================================================

  /**
   * Returns the next bit from the data, it could be a bit of a byte, a
   * checksum bit, or a checksum byte bit.
   * 
   * @return Next bit of data stream.
   * @throws EOFException
   *             If there is no more data to read.
   */
  bool nextBit() {
    datum >>= 1;
    bitpos++;

    // check-bit
    if (bitpos == 8) {
      return xor > 0;
    }

    // need more data
    if (bitpos > 8) {
      if (++offset >= data.length) {
        if (!hasAddedByteChecksum) {
          hasAddedByteChecksum = true;
          datum = xorbyte;
        } else {
          throw new EOFException("");
        }
      } else {
        datum = data[offset] & 0xFF;
        xorbyte ^= datum;
      }

      bitpos = 0;
      xor = 1;
    }
    var result = datum & 1;
    xor ^= result;
    return result != 0;
  }

  /**
   * Check whether there is another bit left in the stream.
   * 
   * @return <code>true</code> if there is data left in the s
   */
  bool hasNextBit() {
    return offset < data.length;
  }

  /**
   * Set the data that this stream is based off.
   * 
   * @param data
   *            Array of data stream is to use.
   * @param offset
   *            Offset in data to start from.
   * @param length
   *            Length of data to read.
   */
  void setData(List<int> srcData, int offsetsrc, int length) {
    data = srcData.getRange(offsetsrc, offsetsrc + length);
    
    offset = -1;
    bitpos = 10;
    xorbyte = 0;
    hasAddedByteChecksum = false;
  }
}

class TapFile {

  List<int> data;
  
  TapFile(List<int> this.data) {
    if (FILE_MAGIC!=bin2String(data, 0, FILE_MAGIC.length)) {
      throw new InvalidFormatException("File is not a TAP file: Header magic is incorrect");
    }
    skipBytes(FILE_MAGIC.length);

    tapVersion = this.nextByte();
    if (tapVersion != 0 && tapVersion != 1) {
      window.alert(
          "Tap version is not understood, version=${tapVersion}, should be either 0 or 1");
    }

    skipBytes(3); // future expansion

    fileDataSize = nextByte() + (nextByte() << 8) + (nextByte() << 16) + (nextByte() << 24);

    rewindOffset = offset;
  }
  
  // ============================================================
  // Static Attributes
  // ============================================================

  /**
   * Magic header string required at start of tap file.
   */
  String FILE_MAGIC = "C64-TAPE-RAW";

  /**
   * Total length of the header block.
   */
  int HEADER_LENGTH = 0x15;

  // ============================================================
  // Attributes
  // ============================================================

  /**
   * Input data.
   */
  //var data = null;

  /**
   * Current offset within input data.
   */
  int offset = 0;

  /**
   * Current offset within input data.
   */
  int rewindOffset = 0;

  /**
   * The version of tap file that is being read.
   */
  int tapVersion = 0;

  /**
   * The file data component size as reported by the tap file header.
   */
  int fileDataSize = 0;

  /**
   * Skip <code>count</code> bytes from the data input. If <code>count</code>
   * will exceed file size then it is trimmed to the file size.
   * 
   * @param count
   *            Number of bytes to skip.
   */
  void skipBytes(int count) {
    offset += count;
    if (offset > data.length) {
      offset = data.length;
    }
  }

  /**
   * Get next byte from the data input. If end-of-file return -1.
   * 
   * @return next byte from the data input, unless end-of-file in which case
   *         it returns -1.
   */
  int nextByte() {
    if (offset == data.length) {
      // end of data
      return -1;
    }
    return data[offset++] & 0xFF;
  }

  // ============================================================
  // ITapeControl Implementation
  // ============================================================

  /**
   * {@inheritDoc}
   */
  //@Override
  void rewind() {
    offset = rewindOffset;
  }

  // ============================================================
  // IPulseData implementation
  // ============================================================

  /**
   * Generate the next pulse for
   * 
   * @return The length of the next pulse, or -1 if end-of-data.
   */
  int nextPulseWidth() {
    int datum = nextByte();

    // TODO
    // Report position every 4096 bits, or at end of file
    //if ((offset & 4095) == 0 || datum == -1) {
    //  Events.postEvent(new EventTapePosition(offset, fileDataSize));
    //}

    if (datum == 0) {
      if (tapVersion != 1) {
        // The data byte value of 00 represents overflow, any
        // pulselength of more than 255*8 cycles.
        datum = 512 << 8;
      } else {
        int _nextByte = nextByte();
        if (_nextByte == -1) {
          print("Unexpected end of tape encountered during extended pulse");
          return -1;
        }
        datum = _nextByte;

        _nextByte = nextByte();
        if (_nextByte == -1) {
          print("Unexpected end of tape encountered during extended pulse");
          return -1;
        }

        datum |= _nextByte << 8;

        _nextByte = nextByte();
        if (_nextByte == -1) {
          print("Unexpected end of tape encountered during extended pulse");
          return -1;
        }

        datum |= _nextByte << 16;
      }
    }
    // Not end of file
    else if (datum != -1) {
      datum <<= 3;
    }

    return datum;
  }
  
  // ============================================================
  // Constructors
  // ============================================================

  /**
   * Constructor to load a Tap file from a file.
   * 
   * @param filepath
   *            The file path of the TAP file.
   * @throws InvalidFormatException
   *             If the file is not a Tap file.
   */
  //public TapFile(String filepath) throws InvalidFormatException {
    /*FileInputStream inputStream = null;
    try {
      offset = 0;

      File file = new File(filepath);
      if (file.length() < HEADER_LENGTH) {
        throw new InvalidFormatException(
            "File is not a TAP file: file too small");
      }

      data = new byte[(int) file.length()];
      int b;
      inputStream = new FileInputStream(file);
      int cnt = 0;
      while ((b = inputStream.read()) != -1) {
        data[cnt++] = (byte) b;
      }
    } catch (IOException ex) {
      EventMessage.showError("Tape failed to load due to:\n"
          + ex.getMessage());
    } finally {
      try {
        if (inputStream != null) {
          inputStream.close();
        }
      } catch (Exception ex) {
        ex.printStackTrace();
      }
    }

    // TODO
    if (FILE_MAGIC!=bin2String(data, 0, FILE_MAGIC.length)) {
      throw new InvalidFormatException(
          "File is not a TAP file: Header magic is incorrect");
    }
    this.skipBytes(FILE_MAGIC.length);

    tapVersion = this.nextByte();
    if (tapVersion != 0 && tapVersion != 1) {
      alert(
          "Tap version is not understood, version=" + tapVersion
              + ", should be either 0 or 1");
    }

    this.skipBytes(3); // future expansion

    fileDataSize = this.nextByte() + (this.nextByte() << 8) + (this.nextByte() << 16)
        + (this.nextByte() << 24);

    rewindOffset = offset;
  //}*/

}

class CsmFile {
  Config config;
  List<int> filedata;
  
  CsmFile(this.config, List<int> this.filedata) {
    rewind();
  }
  
  // ============================================================
  // Static Attributes
  // ============================================================

  /**
   * Size of a tape header.
   */
  int HEADER_SIZE = 192;

  // ============================================================
  // Enumerations
  // ============================================================

  static const TapeState = const {
    "PILOT_HEADER": 0, // S * 0x6A00
    "SYNC_HEADER": 1, // $89, $88 etc
    "HEADER": 2, "HEADER_END_OF_DATA": 3, "PILOT_HEADER_END": 4, // S * 0x4F
    "SYNC_HEADER_REPEAT": 5, // $09, $08 etc
    "HEADER_REPEAT": 6, "HEADER_REPEAT_END_OF_DATA": 7, "PILOT_HEADER_TRAILER": 8, // S *
    // 0x4E
    "SILENCE": 9, // silence(0.4s)
    "PILOT_DATA": 10, // Pilot S * 0x1A00
    "SYNC_DATA": 11, //
    "DATA": 12, "DATA_END_OF_DATA": 13, "PILOT_DATA_END": 14, // Pilot S * 0x4F
    "SYNC_DATA_REPEAT": 15, // 
    "DATA_REPEAT": 16, //
    "DATA_REPEAT_END_OF_DATA": 17, "PILOT_DATA_TRAILER": 18, "END_TAPE": 19
  };

  // ============================================================
  // Attributes
  // ============================================================

  /**
   * Current offset within input data.
   */
  int currentOffset = 0;

  /**
   * Input data.
   */
  List<int> data;

  /**
   * Size of the tapes sub-data blocks.
   */
  int dataSize = 0;

  /**
   * Utility for converting byte data to tape bit data.
   */
  TapeBitDataStream bitData = null;

  /**
   * Utility for converting bit-data to pulse widths.
   */
  PulseWidthsFromBitData pulseData = null;

  /**
   * Utility for generating sync pulse widths.
   */
  PulseWidthSyncGenerator pulseDataSync = null;

  /**
   * Current state of tape play back, e.g. Header, Data
   */
  int state = 0;

  /**
   * Temporary variable used for generating certain numbers of pulses.
   */
  int count = 0;

  // ============================================================
  // ITapeControl Implementation
  // ============================================================

  /**
   * {@inheritDoc}
   */
  //@Override
  void rewind() {
    pulseDataSync = new PulseWidthSyncGenerator(config);
    bitData = new TapeBitDataStream();
    pulseData = new PulseWidthsFromBitData(config, bitData);

    state = TapeState.PILOT_HEADER;
    count = 0x600;// Should be 6a00 but that takes forever
    currentOffset = 0;
  }

  // ============================================================
  // IPulseData Implementation
  // ============================================================

  /**
   * Generate the next pulse for
   * 
   * @return The length of the next pulse, or -1 if end-of-data.
   */
  int nextPulseWidth() {
    if (state == TapeState.PILOT_HEADER) {
      if (--count == 0) {
        state = TapeState.SYNC_HEADER;
        print(state);
        pulseDataSync.reset(false);
      } else {
        return config.S;
      }
    }
    if (state == TapeState.SYNC_HEADER) {
      try {
        return pulseDataSync.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;
        state = TapeState.HEADER;
        print(state);

        pulseData.reset();

        bitData.setData(data, currentOffset, HEADER_SIZE);
        print("header currentOffset = ${currentOffset.toRadixString(16)}");
        int startAddress = (data[currentOffset + 1] & 0xFF)
            | ((data[currentOffset + 2] & 0xFF) << 8);
        print("start address = ${startAddress.toRadixString(16)}");
        int endAddress = (data[currentOffset + 3] & 0xFF)
            | ((data[currentOffset + 4] & 0xFF) << 8);
        print("end address = ${endAddress.toRadixString(16)}");
        dataSize = endAddress - startAddress;
        print("dataSize = " + dataSize.toRadixString(16));
      }
    }
    
    if (state == TapeState.HEADER) {
      try {
        return pulseData.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;

        state = TapeState.HEADER_END_OF_DATA;
        print(state);
        count = 3;
      }
    }
    if (state == TapeState.HEADER_END_OF_DATA) {
      state = TapeState.PILOT_HEADER_END;
      print(state);
      count = 0x4F;
    }
    if (state == TapeState.PILOT_HEADER_END) {
      if (--count == 0) {
        state = TapeState.SYNC_HEADER_REPEAT;
        print(state);
        pulseDataSync.reset(true);
      } else
        return config.S;
    }
    if (state == TapeState.SYNC_HEADER_REPEAT) {
      try {
        return pulseDataSync.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;
        state = TapeState.HEADER_REPEAT;
        print(state);
        pulseData.reset();
        bitData.setData(data, currentOffset, HEADER_SIZE);
        currentOffset += HEADER_SIZE;
      }
    }
    if (state == TapeState.HEADER_REPEAT) {
      try {
        return pulseData.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;
        state = TapeState.HEADER_REPEAT_END_OF_DATA;
        print(state);
        count = 3;
      }
    }
    if (state == TapeState.HEADER_REPEAT_END_OF_DATA) {
      state = TapeState.PILOT_HEADER_TRAILER;
      print(state);
      count = 0x4E;
    }
    if (state == TapeState.PILOT_HEADER_TRAILER) {
      if (--count == 0) {
        state = TapeState.SILENCE;
        print(state);
        count = 400000;
      }
      return config.S;
    }
    if (state == TapeState.SILENCE) {
      if (--count == 0) {
        state = TapeState.PILOT_DATA;
        print(state);
        count = 0x1A00;
      }
      return 0;
    }
    if (state == TapeState.PILOT_DATA) {
      if (--count == 0) {
        state = TapeState.SYNC_DATA;
        print(state);
        pulseDataSync.reset(false);
      }
      return config.S;
    }
    if (state == TapeState.SYNC_DATA) {
      try {
        return pulseDataSync.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;
        state = TapeState.DATA;
        print(state);
        pulseData.reset();
        print("data currentOffset = ${currentOffset.toRadixString(16)}");
        bitData.setData(data, currentOffset, dataSize);
      }
    }
    if (state == TapeState.DATA) {
      try {
        return pulseData.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;
        state = TapeState.DATA_END_OF_DATA;
        print(state);
        count = 3;
      }
    }
    if (state == TapeState.DATA_END_OF_DATA) {
      state = TapeState.PILOT_DATA_END;
      print(state);
      count = 0x4F;
    }
    if (state == TapeState.PILOT_DATA_END) {
      if (--count == 0) {
        state = TapeState.PILOT_DATA_TRAILER;
        print(state);
        count = 0x4E;
      }
      return config.S;
    }
    if (state == TapeState.PILOT_DATA_TRAILER) {
      if (--count == 0) {
        state = TapeState.SYNC_DATA_REPEAT;
        print(state);
        pulseDataSync.reset(true);
      }
      return config.S;
    }
    if (state == TapeState.SYNC_DATA_REPEAT) {
      try {
        return pulseDataSync.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;
        state = TapeState.DATA_REPEAT;
        print(state);
        pulseData.reset();
        bitData.setData(data, currentOffset, dataSize);
        currentOffset += dataSize;
      }
    }
    if (state == TapeState.DATA_REPEAT) {
      try {
        return pulseData.nextPulseWidth();
      } catch (ex) {
        if (!(ex is EOFException )) throw ex;
        state = TapeState.DATA_REPEAT_END_OF_DATA;
        print(state);
      }
    }
    if (state == TapeState.DATA_REPEAT_END_OF_DATA) {
      if (currentOffset == data.length) {
        state = TapeState.END_TAPE;
        print(state);
      } else {
        print("next file: ${currentOffset.toRadixString(16)}/${data.length.toRadixString(16)}");
        state = TapeState.PILOT_HEADER;
        print(state);
        count = 0x1000;
      }
      return 0;
    }
    if (state == TapeState.END_TAPE) {
      return -1;
    }

    throw new Exception("CsmFile::nextPulseWidth INVALID STATE");
  }
  
    // ============================================================
  // Constructors
  // ============================================================

  /**
   * Constructor.
   * 
   * @param filepath
   *            File path to CSM file.
   */
  // CsmFile(String filepath) {

    /*try {
      File f = new File(filepath);
      int size = (int) f.length();
      data = new byte[size];
      int b;
      FileInputStream fis = new FileInputStream(f);
      int cnt = 0;
      while ((b = fis.read()) != -1) {
        data[cnt++] = (byte) b;
      }
      fis.close();
    } catch (IOException ex) {
      EventMessage.showError("Tape failed to load due to:\n"
          + ex.getMessage());
    }*/
  //}
}