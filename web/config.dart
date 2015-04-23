/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

class Config {
  
  //====================================================================
  // Listeners
  //====================================================================
  
  List<Function> _listeners = new List();
  
  void listen(listener(Config config, var param)) {
    _listeners.add(listener);
    listener(this, null);
  }
  
  void _notifyListeners(var param) {
    _listeners.forEach((listener) => listener(this,param));
  }
  
  //====================================================================
  // Configurable fields
  //====================================================================
  
  String _machineDefinitionKey = "usa";
  
  int _speed = 1;
  
  bool memoryAt0400 = false, memoryAt2000 = false, memoryAt4000 = false, memoryAt6000 = false, memoryAtA000 = false;
  
  bool soundChannel1Enabled = true, soundChannel2Enabled = true, soundChannel3Enabled = true, soundChannel4Enabled = true;
  
  bool tapePlay = false;
  
  bool joykeys = true;

  /**
   * Tape excess to add to tape to get Vic20 to understand it.
   * 
   * ATM have to add one as tom.tap is right on the edge of load-able.
   */
  int EXCESS;

  /**
   * Tape small pulse width.
   */
  int S;

  /**
   * Tape medium pulse width.
   */
  int M;

  /**
   * Tape large pulse width.
   */
  int L;
  
  /*
  List<int> colourPalette = const [
    0XFF000000, 0XFFFFFFFF, 0XFF001089, 0XFFCFBF46, 0XFFC61486, 0XFF05B745, 0XFFD01327, 0XFF15D2BE,
    0XFF00469A, 0XFF0099FF, 0XFFCBC0FF, 0XF0FFFFFE, 0XFFD87093, 0XFF90EE90, 0XFFE6D8AD, 0XFFE0FFFF ];  
  */
  
  List<int> colourPalette = const [
    0XFF000000, // color  0 - black
    0XFEFFFFFF, // color  1 - white
    0XFF0000F0, // color  2 - red
    0XFEF0F000, // color  3 - cyan
    0XFF600060, // color  4 - purple
    0XFF00A000, // color  5 - green
    0XFEF00000, // color  6 - blue
    0XFF00D0D0, // color  7 - yellow
    0XFF00A0C0, // color  8 - orange
    0XFF00A0FF, // color  9 - light orange
    0XFF8080F0, // color 10 - pink
    0XFEFFFF00, // color 11 - light cyan
    0XFEFF00FF, // color 12 - light purple
    0XFF00FF00, // color 13 - light green
    0XFEFFA000, // color 14 - light blue
    0XFF00FFFF  // color 15 - light yellow 
  ];
  
  double screenRatio = 1.67, screenScale = 1.00;
  
  //====================================================================
  // Constructors
  //====================================================================
  
  Config() {
    EXCESS = 0;
    
    S = ((0x30 + EXCESS) * 8);

    /**
     * Tape medium pulse width.
     */
    M = ((0x42 + EXCESS) * 8);

    /**
     * Tape large pulse width.
     */
    L = ((0x56 + EXCESS) * 8);
  }

  void toggleJoykeys() {
    joykeys = !joykeys;
    _notifyListeners("joykeys");
  }
  
  String get machineDefinitionKey => _machineDefinitionKey;
  set machineDefinitionKey(String key) {
    _machineDefinitionKey = key;
    _notifyListeners("machineDefinitionKey");
  }

  int get speed => _speed;
  set speed(int value) {
    _speed = value;
    _notifyListeners("speed");
  }
  
  int get frameSkip => (_speed << 1)-1;
}




