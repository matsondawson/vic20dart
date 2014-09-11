/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

 /**
 * Implementation of a 6560/6561 VIC display chip.
 */
abstract class Vic656x {

  Vic20 _machine;
  Config _config;
  List<int> _memory;
  final List<Int32x4> expandMask4bitsTo4Bytes = new List(16);
  final Int32x4 multiColSplitSelect = new Int32x4.bool(true,true,false,false);

  int previousFramesScreenWidth, previousFramesScreenHeight;
  CanvasRenderingContext2D _bufferContext;
  ImageData _bufferImageData;
  
  /**
   * Colour palette that VIC can generate.
   */
  Float32x4List _colourPalette;   
  
  int _noiseOffset = 0;

  int _VERTICAL_BLANK_LAST_ROW;
  int _VISIBLE_SCAN_LINE_CYCLES;
  int _HORIZONTAL_BLANK_CYCLES;
  int _BLANK_LEFT_CYCLES;
  int _TOTAL_SCAN_LINES;
  int _SCAN_LINE_DELAY;

  int _TOTAL_LINE_CYCLES;
  int SCREEN_WIDTH;
  int SCREEN_HEIGHT;

  Uint8ClampedList registers = new Uint8ClampedList(16);

  bool _isBlanking = false;

  int _ptr = 0;
  int _chptr = 0;
  int _resetchptr = 0;
  int _scanLine = 0;
  int _scanCol = 0;
  int _charLineCount = 0;
  int _displayColCount = 0;
  int _displayRowCount = 0;
  int _chdata = 0;
  int _nextchdata = 0;
  int _col = 0;
  int _nextcol = 0;
  int _nextnextcol = 0;
  int _ch = 0;
  int _precount = 0;
  bool _hasPreCycled = false;

  int _base = 0;
  int _colbase = 0;
  int _charrom = 0;
  Float32x4 _borderColour, _backColour;
  Float32x4List _screenData;
  Float32x4List _multicol = new Float32x4List(4);
  int _charHeightShift = 0;
  
  /**
   * On NTSC Vic20's the scan-line counter updates in the middle of the
   * scan-line.
   */
  int _scanLineCounterDelay = 0;

  // ============================================================
  // Constructors
  // ============================================================

  // Init display canvas
  CanvasElement _screenCanvas;
  CanvasRenderingContext2D _screenContext;
  CanvasElement _bufferCanvas;

  Vic656x(this._config, this._machine, this._memory) {
    for(var i=0; i<16; i++) expandMask4bitsTo4Bytes[i] = new Int32x4.bool((i&8)!=0,(i&4)!=0,(i&2)!=0,(i&1)!=0);

    _colourPalette = new Float32x4List(16);
    for(var i=0; i<_config.colourPalette.length; i++) {
      var c = _config.colourPalette[i];
      _colourPalette[i] = new Float32x4.fromInt32x4Bits(new Int32x4(c,c,c,c));//.toFloat32x4();
    }
    
    reset();
    
    sampleRate = AudioHook.hook(onAudioProcess);
    hasAudio = sampleRate!=-1;
    _renderingBuffer = new Float32List(_renderingBufferSize);
  }
  
  void onAudioProcess(AudioProcessingEvent event) {
    if(((_sndCount - _sndReadCount)&_mask)>=2048) {
      Float32List channelData = event.outputBuffer.getChannelData(0);
      
      int end = (_sndReadCount+2048) & _mask;
      if (end<_sndReadCount) {
        channelData
            ..setRange(0, _renderingBufferSize-_sndReadCount, _renderingBuffer, _sndReadCount)
            ..setRange(_renderingBufferSize-_sndReadCount, 2048, _renderingBuffer, 0);
      } else {
        channelData.setRange(0, 2048, _renderingBuffer, _sndReadCount);
      }

      _sndReadCount = end;
    }
    // else audio starved 
  }

  int _soundDivider = 0;
  int frameIndex = 0;

  int _fromVicAddress(address) => (address & 0x1fff) | (((address & 0x2000) << 2) ^ 0xFFFF) & 0x8000;
  
  int getMatrixBase()  => _fromVicAddress(_base);
  int getColorBase()   => _fromVicAddress(_colbase);
  int getCharMapBase() => _fromVicAddress(_charrom);
  
  void cycle();
  
  /**
   * Reset the VIC.
   */
  void reset() {
    _vicSoundRenderRate = _machine.machineDefinition.clockRate()/16.0;

    _TOTAL_LINE_CYCLES = (_HORIZONTAL_BLANK_CYCLES + _VISIBLE_SCAN_LINE_CYCLES);
    SCREEN_WIDTH = (_VISIBLE_SCAN_LINE_CYCLES * 4);
    SCREEN_HEIGHT = (_TOTAL_SCAN_LINES - _VERTICAL_BLANK_LAST_ROW);

    registers.fillRange(0, registers.length, 0);
    
    _ch=0;
    
    // Init any variables that are only set when they registers are written
    for (var i = 0; i < 16; i++) write(i,defaultRegisterValues()[i]);

    videoBegin();
  }
  
  List<int> defaultRegisterValues();
  
  /**
   * Beginning of video frame.
   */
  void videoBegin() {
    _isBlanking = true;
    _scanLine = _scanCol = _ptr = 0;
    _displayRowCount = _displayColCount = -1;
    _scanLineCounterDelay = _SCAN_LINE_DELAY;

    if (frameIndex==0) _displayFrame();
    frameIndex = (frameIndex+1)&_config.frameSkip;
  }

  void _displayInit() {
    // When canvas context is lost the whole canvas
    // gets buggered so we need to replace with a new one
    _screenCanvas = new CanvasElement();
    _screenCanvas.attributes["id"]="vic20screen";

    querySelector("#vic20screen").replaceWith(_screenCanvas);
    _screenCanvas.onClick.listen((event) => fullscreen());
    
    _screenContext = _screenCanvas.context2D;
    
    previousFramesScreenWidth = SCREEN_WIDTH;
    previousFramesScreenHeight = SCREEN_HEIGHT;
    
    _bufferCanvas = new CanvasElement()
        ..width  = SCREEN_WIDTH
        ..height = SCREEN_HEIGHT;

    _bufferContext = _bufferCanvas.context2D;
    _bufferImageData = _bufferContext.getImageData(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);

    print("""Re-init screen buffer
      Screen size: $SCREEN_WIDTH x $SCREEN_HEIGHT
      Screen canvas size: ${_screenCanvas.width} x ${_screenCanvas.height}""");

    _screenCanvas
      ..width  = (SCREEN_WIDTH  * _config.screenScale * _config.screenRatio).floor()
      ..height = (SCREEN_HEIGHT * _config.screenScale).floor();
    
    _screenData = new Float32x4List.view((_bufferImageData.data as Uint8ClampedList).buffer);
  }
  
  int _contextCheckCountdown = 0;
  void _displayFrame() {
    bool didInit = false;
    if (_bufferCanvas==null || SCREEN_WIDTH!=previousFramesScreenWidth || SCREEN_HEIGHT!=previousFramesScreenHeight) {
      _displayInit();
      didInit = true;
      _contextCheckCountdown=100;
    }
          
    _bufferContext.putImageData(_bufferImageData, 0, 0);
    _screenContext.drawImageScaled(_bufferCanvas, 0, 0, _screenCanvas.width, _screenCanvas.height);
  }
    
  
  // ============================================================
  // IRam implementation
  // ============================================================

  /**
   * {@inheritDoc}
   */
  int read(int regnum) {
    //cycle();
    //_hasPreCycled=true;
    return registers[regnum & 0xF];
  }

  int invisibleRead(int regnum) => registers[regnum & 0xF];
  
  /**
   * {@inheritDoc}
   */
  void write(int regnum, int value) {
    //cycle();
    //_hasPreCycled=true;
    
    regnum &= 0xF;
    // cannot write to raster
    if (regnum != 4) {
      var preValue = registers[regnum];
      registers[regnum] = value;
      switch (regnum) {
      case 0x02:
        _base = ((registers[5] >> 4) << 10) | ((value & 0x80) << 2);
        _colbase = 0x1400 + ((value & 128) << 2);
        break;
      case 0x03:
        _charHeightShift = 3 + (value & 1);
        // retain raster value
        registers[regnum] = (value & 0x7F) | (preValue & 0x80);
        break;
      case 0x05:
        _base = ((value >> 4) << 10) | ((registers[2] & 0x80) << 2);
        _charrom = (value & 0xF) << 10;
        break;
      case 0x0A:
        _maxCounts = _maxCounts.withW((128 - ((value + 1) & 0x7F)).toDouble());
        _soundCountEn  = _soundCountEn.withFlagW(value >= 128);
        break;
      case 0x0B:
        _maxCounts = _maxCounts.withX((128 - ((value + 1) & 0x7F)).toDouble());
        _soundCountEn = _soundCountEn.withFlagX(value >= 128);
        break;
      case 0x0C:
        _maxCounts = _maxCounts.withY((128 - ((value + 1) & 0x7F)).toDouble());
        _soundCountEn = _soundCountEn.withFlagY(value >= 128);
        break;
      case 0x0D:
        _maxCounts = _maxCounts.withZ((128 - ((value + 1) & 0x7F)).toDouble());
        _soundCountEn = _soundCountEn.withFlagZ(value >= 128);
        break;
      case 0x0E:
        // auxColour
        _volumes = new Float32x4.splat((value & 0xF) / 64);
        _multicol[3] = _colourPalette[value >> 4];
        break;
      case 0x0F:
        _borderColour = _colourPalette[value & 7];
        _backColour = _colourPalette[value >> 4];
        _multicol[1] = _borderColour;
        _multicol[0] = _backColour;
        break;
      }
    }
  }
  

  //==================================================================================
  // AUDIO GENERATION
  //==================================================================================
  
  bool hasAudio;
  double sampleRate;
  
  /**
   * Offset into sndData for next sound sample.
   */
  int _sndCount = 0, _sndReadCount = 0;
  
  double _cs = 0.0;

  /**
   * Buffer for sound event messages.
   */
  static const int _renderingBufferSize = 8192, _mask = 8191;
  Float32List _renderingBuffer;
  double _vicSoundRenderRate;
  
  final Float32x4 fZero = new Float32x4.zero();
  Float32x4 _volumes = new Float32x4.zero();
  Float32x4 _soundCounts= new Float32x4.zero();
  Float32x4 _maxCounts= new Float32x4.splat(255.0);
  Int32x4 _soundStates= new Int32x4.bool(false,false,false,false);
  final Float32x4 _soundCountInc = new Float32x4(0.25, 0.5, 1.0, 0.125);// x, y, z, w ordering!!?!?
  Int32x4 _soundCountEn = new Int32x4.bool(false,false,false,false);
  
  void _genAudio() {
    if (sampleRate==null) return;
    _soundDivider = 0;
    
    // incement counters
    _soundCounts += _soundCountInc;
    // 
    Int32x4 countsExceeded = _soundCounts.greaterThanOrEqual(_maxCounts);
    // reset exceeded counters
    _soundCounts = countsExceeded.select(fZero, _soundCounts);
    // toggle exceeded counters that are enabled
    _soundStates = _soundStates ^ countsExceeded;
    // Noise channel may or may not toggle
    if (countsExceeded.flagZ) {
      _soundStates = _soundStates.withFlagZ(  ((_noisePattern[_noiseOffset >> 3] >> (_noiseOffset & 7)) & 1)>0 );
      _noiseOffset = (_noiseOffset+1)&1023;
    }
    
    _cs += sampleRate;
    if (_cs>=_vicSoundRenderRate) {
      _cs-=_vicSoundRenderRate;
      // Only add if the buffer isn't full
      int plus1 = (_sndCount+1)&_mask;
      if (plus1!=_sndReadCount) {
        Float32x4 channelsOut = (_soundStates & _soundCountEn).select(_volumes, fZero);
        _renderingBuffer[_sndCount] = _volumes.x /*hack for dac*/ + channelsOut.w + channelsOut.x + channelsOut.y + channelsOut.z;
        _sndCount=plus1;
      }
    }
  }
  
  /**
   * TODO make own noise pattern
   */
  final Uint8ClampedList _noisePattern = new Uint8ClampedList.fromList([ 7, 30, 30, 28, 28,
      62, 60, 56, 120, 248, 124, 30, 31, 143, 7, 7, 193, 192, 224, 241,
      224, 240, 227, 225, 192, 224, 120, 126, 60, 56, 224, 225, 195, 195,
      135, 199, 7, 30, 28, 31, 14, 14, 30, 14, 15, 15, 195, 195, 241,
      225, 227, 193, 227, 195, 195, 252, 60, 30, 15, 131, 195, 193, 193,
      195, 195, 199, 135, 135, 199, 15, 14, 60, 124, 120, 60, 60, 60, 56,
      62, 28, 124, 30, 60, 15, 14, 62, 120, 240, 240, 224, 225, 241, 193,
      195, 199, 195, 225, 241, 224, 225, 240, 241, 227, 192, 240, 224,
      248, 112, 227, 135, 135, 192, 240, 224, 241, 225, 225, 199, 131,
      135, 131, 143, 135, 135, 199, 131, 195, 131, 195, 241, 225, 195,
      199, 129, 207, 135, 3, 135, 199, 199, 135, 131, 225, 195, 7, 195,
      135, 135, 7, 135, 195, 135, 131, 225, 195, 199, 195, 135, 135, 143,
      15, 135, 135, 15, 207, 31, 135, 142, 14, 7, 129, 195, 227, 193,
      224, 240, 224, 227, 131, 135, 7, 135, 142, 30, 15, 7, 135, 143, 31,
      7, 135, 193, 240, 225, 225, 227, 199, 15, 3, 143, 135, 14, 30, 30,
      15, 135, 135, 15, 135, 31, 15, 195, 195, 240, 248, 240, 112, 241,
      240, 240, 225, 240, 224, 120, 124, 120, 124, 112, 113, 225, 225,
      195, 195, 199, 135, 28, 60, 60, 28, 60, 124, 30, 30, 30, 28, 60,
      120, 248, 248, 225, 195, 135, 30, 30, 60, 62, 15, 15, 135, 31, 142,
      15, 15, 142, 30, 30, 30, 30, 15, 15, 143, 135, 135, 195, 131, 193,
      225, 195, 193, 195, 199, 143, 15, 15, 15, 15, 131, 199, 195, 193,
      225, 224, 248, 62, 60, 60, 60, 60, 60, 120, 62, 30, 30, 30, 15, 15,
      15, 30, 14, 30, 30, 15, 15, 135, 31, 135, 135, 28, 62, 31, 15, 15,
      142, 62, 14, 62, 30, 28, 60, 124, 252, 56, 120, 120, 56, 120, 112,
      248, 124, 30, 60, 60, 48, 241, 240, 112, 112, 224, 248, 240, 248,
      120, 120, 113, 225, 240, 227, 193, 240, 113, 227, 199, 135, 142,
      62, 14, 30, 62, 15, 7, 135, 12, 62, 15, 135, 15, 30, 60, 60, 56,
      120, 241, 231, 195, 195, 199, 142, 60, 56, 240, 224, 126, 30, 62,
      14, 15, 15, 15, 3, 195, 195, 199, 135, 31, 14, 30, 28, 60, 60, 15,
      7, 7, 199, 199, 135, 135, 143, 15, 192, 240, 248, 96, 240, 240,
      225, 227, 227, 195, 195, 195, 135, 15, 135, 142, 30, 30, 63, 30,
      14, 28, 60, 126, 30, 60, 56, 120, 120, 120, 56, 120, 60, 225, 227,
      143, 31, 28, 120, 112, 126, 15, 135, 7, 195, 199, 15, 30, 60, 14,
      15, 14, 30, 3, 240, 240, 241, 227, 193, 199, 192, 225, 225, 225,
      225, 224, 112, 225, 240, 120, 112, 227, 199, 15, 193, 225, 227,
      195, 192, 240, 252, 28, 60, 112, 248, 112, 248, 120, 60, 112, 240,
      120, 112, 124, 124, 60, 56, 30, 62, 60, 126, 7, 131, 199, 193, 193,
      225, 195, 195, 195, 225, 225, 240, 120, 124, 62, 15, 31, 7, 143,
      15, 131, 135, 193, 227, 227, 195, 195, 225, 240, 248, 240, 60, 124,
      60, 15, 142, 14, 31, 31, 14, 60, 56, 120, 112, 112, 240, 240, 248,
      112, 112, 120, 56, 60, 112, 224, 240, 120, 241, 240, 120, 62, 60,
      15, 7, 14, 62, 30, 63, 30, 14, 15, 135, 135, 7, 15, 7, 199, 143,
      15, 135, 30, 30, 31, 30, 30, 60, 30, 28, 62, 15, 3, 195, 129, 224,
      240, 252, 56, 60, 62, 14, 30, 28, 124, 30, 31, 14, 62, 28, 120,
      120, 124, 30, 62, 30, 60, 31, 15, 31, 15, 15, 143, 28, 60, 120,
      248, 240, 248, 112, 240, 120, 120, 60, 60, 120, 60, 31, 15, 7, 134,
      28, 30, 28, 30, 30, 31, 3, 195, 199, 142, 60, 60, 28, 24, 240, 225,
      195, 225, 193, 225, 227, 195, 195, 227, 195, 131, 135, 131, 135,
      15, 7, 7, 225, 225, 224, 124, 120, 56, 120, 120, 60, 31, 15, 143,
      14, 7, 15, 7, 131, 195, 195, 129, 240, 248, 241, 224, 227, 199, 28,
      62, 30, 15, 15, 195, 240, 240, 227, 131, 195, 199, 7, 15, 15, 15,
      15, 15, 7, 135, 15, 15, 14, 15, 15, 30, 15, 15, 135, 135, 135, 143,
      199, 199, 131, 131, 195, 199, 143, 135, 7, 195, 142, 30, 56, 62,
      60, 56, 124, 31, 28, 56, 60, 120, 124, 30, 28, 60, 63, 30, 14, 62,
      28, 60, 31, 15, 7, 195, 227, 131, 135, 129, 193, 227, 207, 14, 15,
      30, 62, 30, 31, 15, 143, 195, 135, 14, 3, 240, 240, 112, 224, 225,
      225, 199, 142, 15, 15, 30, 14, 30, 31, 28, 120, 240, 241, 241, 224,
      241, 225, 225, 224, 224, 241, 193, 240, 113, 225, 195, 131, 199,
      131, 225, 225, 248, 112, 240, 240, 240, 240, 240, 112, 248, 112,
      112, 97, 224, 240, 225, 224, 120, 113, 224, 240, 248, 56, 30, 28,
      56, 112, 248, 96, 120, 56, 60, 63, 31, 15, 31, 15, 31, 135, 135,
      131, 135, 131, 225, 225, 240, 120, 241, 240, 112, 56, 56, 112, 224,
      227, 192, 224, 248, 120, 120, 248, 56, 241, 225, 225, 195, 135,
      135, 14, 30, 31, 14, 14, 15, 15, 135, 195, 135, 7, 131, 192, 240,
      56, 60, 60, 56, 240, 252, 62, 30, 28, 28, 56, 112, 240, 241, 224,
      240, 224, 224, 241, 227, 224, 225, 240, 240, 120, 124, 120, 60,
      120, 120, 56, 120, 120, 120, 120, 112, 227, 131, 131, 224, 195,
      193, 225, 193, 193, 193, 227, 195, 199, 30, 14, 31, 30, 30, 15, 15,
      14, 14, 14, 7, 131, 135, 135, 14, 7, 143, 15, 15, 15, 14, 28, 112,
      225, 224, 113, 193, 131, 131, 135, 15, 30, 24, 120, 120, 124, 62,
      28, 56, 240, 225, 224, 120, 112, 56, 60, 62, 30, 60, 30, 28, 112,
      60, 56, 63 ]);

}
