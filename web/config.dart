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
  
  List<int> colourPalette = const [
    0XFF000000, 0XFFFFFFFF, 0XFF001089, 0XFFCFBF46, 0XFFC61486, 0XFF05B745, 0XFFD01327, 0XFF15D2BE,
    0XFF00469A, 0XFF0099FF, 0XFFCBC0FF, 0XF0FFFFFE, 0XFFD87093, 0XFF90EE90, 0XFFE6D8AD, 0XFFE0FFFF ];
  
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




