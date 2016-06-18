/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

/**
 * Copyright matsondawson@gmail.com 2013
 */
class Vic20 extends IeeeDevice {
  Config config;
  MachineDefinition machineDefinition;
  Cpu6502 _cpu;
  Vic656x _vic;
  Via1 _via1;
  Via2 _via2;
  TapeDrive tapeDrive;
  Ieee _ieee;
  Keyboard _keyboard;
  EventManager _eventManager;
  
  Uint8ClampedList _memory, _memoryExec, _memoryBp;

  List<Function> _readFuncs            = new List(65536>>4);
  List<Function> _invisibleReadFuncs   = new List(65536>>4);
  List<Function> _writeFuncs           = new List(65536>>4);
  List<Function> _invisibleWriteFuncs  = new List(65536>>4);

  bool stop = false, running = false;
  int nextFrameTime = 0;
  double subFrameTime = 0.0;
  int loadPrgCntr;
  
  bool isDebugging = false;
  
  Function read;
  Function write;
  
  List<List<int>> loadPrgBinaryData;
  
  // TODO
  void debug() {
    //
  }
  
  Vic20(this.machineDefinition) {
    read = readNormal;
    write = writeNormal;
    
    config = new Config();
    _eventManager = new EventManager();
    
    _memory     = new Uint8ClampedList(65536);
    _memoryExec = new Uint8ClampedList(65536);
    _memoryBp   = new Uint8ClampedList(65536);
    
    _cpu = new Cpu6502(this);
    _vic = machineDefinition.isPal?new Vic6561(config, this, _memory):new Vic6560(config, this, _memory);
    
    _keyboard = new Keyboard(config, this);

    // TODO no need to do this can just extend via
    _ieee = new Ieee();
    tapeDrive = new TapeDrive(config, _eventManager);
    _via1 = new Via1(config, _keyboard, tapeDrive);
    _via2 = new Via2(config, _keyboard, tapeDrive);
    
    // TODO seems a bit backwards
    _keyboard._via2 = _via2;
    
    _ieee.addDevice(this);
    
    reset();
  }
  
  void reinit(MachineDefinition machineDefinition, void andThen()) {
    config.machineDefinitionKey = machineDefinition.key;
    stopExecution(() {
      this.machineDefinition = machineDefinition;
      AudioHook.unhook();
      _vic = machineDefinition.isPal?new Vic6561(config, this, _memory):new Vic6560(config, this, _memory);
      reset();
      andThen();
    });
  }
  
  // **********************************
  // Methods
  // **********************************
  
  int readNormal(offset)    => (_readFuncs[offset>>4])(offset);
  int invisibleRead(offset) => (_invisibleReadFuncs[offset>>4])(offset);
  
  int readDebug(offset) {
    _memoryExec[offset]|=8; // Meaning has been read
    return (_readFuncs[offset>>4])(offset);
  }

  void writeDebug(offset, value) {
    _memoryExec[offset]=16; // Meaning has been written
    (_writeFuncs[offset>>4])(offset,value);
  }
  
  void writeNormal(offset, value)    { (_writeFuncs[offset>>4])(offset,value); }
  void invisibleWrite(offset, value) { (_invisibleWriteFuncs[offset>>4])(offset,value); }
  
  int read0(offset)             => 0;
  int readMem(offset)           => _memory[offset];
  int readVia1(offset)          => _via1.read(offset);
  int invisibleReadVia1(offset) => _via1.invisibleRead(offset);
  int readVia2(offset)          => _via2.read(offset);
  int invisibleReadVia2(offset) => _via2.invisibleRead(offset);
  int readVic(offset)           => _vic.read(offset);
  int invisibleReadVic(offset)  => _vic.invisibleRead(offset);
  
  void write0(offset, value)              {}
  void writeMem(offset, value)            { _memory[offset] = value; }
  void writeVia1(offset, value)           { _via1.write(offset,value); }
  void invisibleWriteVia1(offset, value)  { _via1.invisibleWrite(offset,value); }
  void writeVia2(offset, value)           { _via2.write(offset,value); }
  void invisibleWriteVia2(offset, value)  { _via2.invisibleWrite(offset,value); }
  void writeVic(offset, value)            { _vic.write(offset,value); }
  
  bool lastAtn = null;
  
  bool atn() {
    // VIA-2 PA7 = ATN
    bool newAtn = ((_via2.read(1)&_via2.read(3))>>7)>0;
    if (newAtn!=lastAtn) {
      lastAtn=newAtn;
      print("vic20 atn ${newAtn}");
    }
    return newAtn;
  }
  
  bool lastclk=null;
  bool clk() {
    bool newClk = _via1.ca2;
    if (lastclk!=newClk) {
      lastclk=newClk;
      print("Vic20 clk ${newClk}");
    }
    return newClk;
  }
  
  bool lastdata=null;
  bool data() {
    bool newData = ((_via1.invisibleRead(0xC)>>5)&1)>0; //VIA1 - CB2
    if (lastdata!=newData) {
      lastdata=newData;
      print("Vic20 data ${newData}");
    }
    return newData;
  }

  bool hasIrq() => _via1.hasInterrupt;
  bool hasNmi() => _via2.hasInterrupt;
  
  void softreset() {
    print("Vic20 soft reset");
    _cpu.reset();
    //vic1541.cpu.reset();
  }
  
  void softReset() {
    print("Vic20 soft reset");
    _cpu.reset();
  }
  
  void reset() {
    print("Vic20 hard reset");
    
    // Init ram
    _memory
      ..fillRange(0, _memory.length, 0xCE)
      ..setAll(0x8000, machineDefinition.charRom)
      ..setAll(0xC000, machineDefinition.basicRom)
      ..setAll(0xE000, machineDefinition.kernalRom);
    
    _memoryBp  .fillRange(0, _memoryBp.length, 0x00);
    _memoryExec.fillRange(0, _memoryExec.length, 0x00);

    _readFuncs           .fillRange(0, _readFuncs.length, readMem);
    _invisibleReadFuncs  .fillRange(0, _invisibleReadFuncs.length, readMem);
    _writeFuncs          .fillRange(0, _writeFuncs.length, writeMem);
    _invisibleWriteFuncs .fillRange(0, _invisibleWriteFuncs.length, writeMem);

    // VIC ranges
    for(var i=0x9000; i<0x9100; i+=16) {
      _readFuncs[i>>4]=readVic;
      _invisibleReadFuncs[i>>4]=invisibleReadVic;
      _writeFuncs[i>>4]=writeVic;
      _invisibleWriteFuncs[i>>4]=writeVic;
    }
    
    // VIA2 ranges
    for(var i=0x9110; i<=0x93F0; i+=32) {
      _readFuncs[i>>4]=readVia2;
      _invisibleReadFuncs[i>>4]=invisibleReadVia2;
      _writeFuncs[i>>4]=writeVia2;
      _invisibleWriteFuncs[i>>4]=invisibleWriteVia2;
    }
    
    // VIA1 Ranges
    for(var i=0x9120; i<=0x93E0; i+=64) {
      _readFuncs[i>>4]=readVia1;
      _invisibleReadFuncs[i>>4]=invisibleReadVia1;
      _writeFuncs[i>>4]=writeVia1;
      _invisibleWriteFuncs[i>>4]=invisibleWriteVia1;
    }
   
    // Character Map
    _writeFuncs          .fillRange(0x8000>>4, 0x9000>>4, write0);
    _invisibleWriteFuncs .fillRange(0x8000>>4, 0x9000>>4, write0);
    
    // Kernel and basic Rom
    _writeFuncs          .fillRange(0xA000>>4, 0x10000>>4, write0);
    _invisibleWriteFuncs .fillRange(0xA000>>4, 0x10000>>4, write0);

		updateMemoryModules();
		
    loadPrgCntr = 2;
    
    _cpu.reset();
    _via1.reset();
    _via2.reset();
    _vic.reset();
    
    //vic1541.reset();
  }
  
  void updateMemoryModules() {
    Function write0400 = config.memoryAt0400?writeMem:write0;
    _writeFuncs          .fillRange(0x0400>>4, 0x1000>>4, write0400);
    _invisibleWriteFuncs .fillRange(0x0400>>4, 0x1000>>4, write0400);

    Function write2000 = config.memoryAt2000?writeMem:write0;
    _writeFuncs          .fillRange(0x2000>>4, 0x4000>>4, write2000);
    _invisibleWriteFuncs .fillRange(0x2000>>4, 0x4000>>4, write2000);

    Function write4000 = config.memoryAt4000?writeMem:write0;
    _writeFuncs          .fillRange(0x4000>>4, 0x6000>>4, write4000);
    _invisibleWriteFuncs .fillRange(0x4000>>4, 0x6000>>4, write4000);

    Function write6000 = config.memoryAt6000?writeMem:write0;
    _writeFuncs          .fillRange(0x6000>>4, 0x8000>>4, write6000);
    _invisibleWriteFuncs .fillRange(0x6000>>4, 0x8000>>4, write6000);
    Function writeA000 = config.memoryAtA000?writeMem:write0;
    _writeFuncs          .fillRange(0xA000>>4, 0xC000>>4, writeA000);
    _invisibleWriteFuncs .fillRange(0xA000>>4, 0xC000>>4, writeA000);
  }

  void execute() {
    print("Vic20 execute");

    if (running) {
      print("Already running");
      return;
    }
    
    nextFrameTime = new DateTime.now().millisecondsSinceEpoch;
    stop = false;
    running = true;
    oneFrame();
  }
  
  Function callAfterStop;
  void stopExecution([void andThen()]) {
    this.callAfterStop = andThen;
    stop = true;
  }
  
  var oneFrameTimeSum = 0;
  var timeloop = 100;
  var sw = new Stopwatch();
  Element frameTimeEl = querySelector("#frameTime");
  void oneFrame() {
    int startFrameTime = new DateTime.now().millisecondsSinceEpoch;
    
    if (!stop) {
      sw..reset()..start();
      for(int i=machineDefinition.cyclesPerFrame(); i!=0; i--) {
        _via1.cycleUp();
        _via2.cycleUp();
        _cpu.cycle();
        _via1.cycleDown();
        _via2.cycleDown();
        _vic.cycle();
      }
      oneFrameTimeSum += sw.elapsedMicroseconds;
      sw.stop();
      if (timeloop--==0) {
        frameTimeEl.innerHtml = "${oneFrameTimeSum/100000} ms";
        oneFrameTimeSum = 0;
        timeloop = 100;
      }
    }
    
    // If a program is waiting to load and the kernel is ready
    if(loadPrgBinaryData!=null && (_memory[43]!=0 || _memory[44]!=0) && loadPrgCntr--==0) {
      // TODO sort out tape loading
      /*if(loadPrgBinaryData=="tape") {
        _memory[631]=131;
        _memory[198]=1;
        config.tapePlay = true;
      }
      else {*/
        loadPrgFileData(loadPrgBinaryData);
      //}
      loadPrgBinaryData = null;
    }
    
    // Wait until next frame
    double frameTime = machineDefinition.frameTimeMs()/config.speed;
    subFrameTime += frameTime;
    nextFrameTime += subFrameTime.floor();
    subFrameTime -= subFrameTime.floor();

    int now = new DateTime.now().millisecondsSinceEpoch;
    int timeWaitUntilNextFrame = nextFrameTime - now;
    if (timeWaitUntilNextFrame<0) {
      timeWaitUntilNextFrame=0;
      nextFrameTime = now;
    }
    if (!stop) {
      new Timer( new Duration(milliseconds:timeWaitUntilNextFrame), oneFrame);
    } else {
      running = false;
      if (callAfterStop!=null) {
        var x = callAfterStop;
        callAfterStop = null;
        x();
      }
    }
  }
  
  void loadPrgFileData(List<List<int>> bindatas) {
    // TODO this is wrong
    int from, endloc;
    for(var i=0; i<bindatas.length; i++) {
      var bindata = bindatas[i];
      from = bindata[0] | (bindata[1]<<8);
      int length = bindata.length-2;
      endloc = from + bindata.length-2;
      
      print("Loading prg from 0x${from.toRadixString(16)} to 0x${endloc.toRadixString(16)}");
      
      // for(int cnt=2; cnt<bindata.length;cnt++) mem[from+cnt-2]=bindata[cnt];
      _memory.setRange(from, from + length, bindata, 2);
    }
    
    // Start cartridge
    if (from==0xA000) {
      softreset();
      return;
    }
    
    // Routine to fix basic pointers and start basic program
    List<int> bootStrap = [
                           0x20, 0x33, 0xc5, // JSR $C533 / 50483; re-link line pointers
                           0xa9, endloc & 0xFF, 0x85, 45, // update variable pointer low
                           0xA9, endloc >> 8, 0x85, 46, // update variable pointer high
                           0x20, 0x59, 0xc6, // JSR $C659 / 50777 ); CLR, reset TXTPTR
                           0x4c, 0xae, 0xc7, // JMP $C7AE / 51118 ); execute next statement
                           0x60 // RTS
                           ];
    // for(var i = 0; i < bootStrap.length; i++) mem[320 + i]=bootStrap[i];
    _memory.setRange(320, 320+bootStrap.length, bootStrap);
    insertKeys("SYS320\r");
  }
  
  /**
   * This is generally called by the prgToJs.php script callback. 
   */
  List<String> _sourceStrings;
  void loadPrg(List<String> sourceStrings) {
    List<List<int>> prgBinaryDatas = new List();
    sourceStrings.forEach((sourceString) => prgBinaryDatas.add(sinToBin(sourceString)));
    loadPrgFromData(prgBinaryDatas);
  }

  void loadPrgFromData(List<List<int>> prgBinaryDatas) {
    stopExecution();
    int from = setPrgMemory(prgBinaryDatas.last);
    if (from==0xA000) {
      reset();
      print("Cartridge load");
      loadPrgFileData(prgBinaryDatas);
      execute();
    } else {
      print("PRG load");
      loadPrgBinaryData = prgBinaryDatas;
      reset();
      execute();
    }
  }

  int setPrgMemory(List<int> bindata) {
    int from = bindata[0]|(bindata[1]<<8);
    int endloc = from+bindata.length-2;
    
    print("setPrgMemory loading prg from 0x${from.toRadixString(16)} to 0x${endloc.toRadixString(16)}");
    
    config.memoryAt0400 = config.memoryAt2000 = config.memoryAt4000 = config.memoryAt6000 = config.memoryAtA000 = false;

    if (from==0xA000) {
      // Cartridge
      print("Cartridge detected");
    } else {//0x401
      if (from<0x1000) {
        // +3k
        config.memoryAt0400=true;
        print("+3k detected");
      } else {
        // Unexpanded
        if (from>=0x1200) {
          // +24k
          config.memoryAt2000 = config.memoryAt4000 = config.memoryAt6000 = true;
          print("+8k or more detected");
        }
      }
    }
    updateMemoryModules();
    
    return from;
  }

  void insertKeys(String keys) {
    print("insertKeys: $keys");
    int offset=0x277;
    for(int i=0; i<keys.length; i++) {
      _memory[offset++] = keys.codeUnitAt(i);// .charCodeAt(i);
    }
    _memory[0xC6] = keys.length;                 
  }
}
