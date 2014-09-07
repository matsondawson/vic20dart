/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

class Via2 extends Via6522 {
  Config _config;
  TapeDrive _tapeDrive;
  Keyboard _keyboard;
  
  int _lastPcrCa2;
  
  Via2(this._config, this._keyboard, this._tapeDrive) : super(0x9110,"VIA2");
  
  int read(int reg) {
    // Ieee not implemented yet hence
    pins_ira = 1;
    
    if (_config.tapePlay) pins_ira |= 64; else pins_ira &= (64^0xFF);
    
    // Serial ATN out 0x80 as input should always be 0
    // Serial CLK and data should be whatever is on the IEEE bus
    // For test purposes until implemented this is Clock = 1, Data = 0
    // pins_ira |= 194; // Pretend a disk drive is present

    pins_irb = 0xFF;
    
    // Handle joystick actions
    if (_keyboard.joystickFire) pins_ira |= 32; else pins_ira &= (32^0xFF);
    if (_keyboard.joystickLeft) pins_ira |= 16; else pins_ira &= (16^0xFF);
    if (_keyboard.joystickUp)   pins_ira |= 4;  else pins_ira &= (4^0xFF);
    if (_keyboard.joystickDown) pins_ira |= 8;  else pins_ira &= (8^0xFF);
    return super.read(reg);
  }

  void cycleUp() {
    super.cycleUp();

    int pcrCa2 = (registers[12] >> 1) & 7;

    if (pcrCa2 != _lastPcrCa2) {
      if (pcrCa2 == 7) {
        _tapeDrive.triggerTapeMotor(false);
      } else if (pcrCa2 == 6) {
        _tapeDrive.triggerTapeMotor(true);
      }
      _lastPcrCa2 = pcrCa2;
    }
  }
  

}