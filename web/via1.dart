/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

class Via1 extends Via6522 {
  Config _config;
  TapeDrive _tapeDrive;
  Keyboard _keyboard;
  
  Via1(this._config, this._keyboard, this._tapeDrive) : super(0x9120,"VIA1");
  
  int read(int regnum) {
    switch (regnum&0xF) {
      case 0x0:
      case 0x1:
      case 0xF:
        // Output on pins of ORB depends on data direction register.
        pins_ira = pins_irb = 0;
        var orb = registers[0], ora = registers[1], ddrb = registers[2], ddra = registers[3];
        var column = ((orb & ddrb) ^ 0xFF) & 0xFF, row = ((ora & ddra) ^ 0xFF) & 0xFF;

        for (var i = 0; i < 8; i++) {
          if ((column & (1 << i)) != 0) pins_ira |= _keyboard.keysdown[i];
          pins_irb |= (((_keyboard.keysdown)[i] & row)!=0) ? (1 << i) : 0;
        }

        if ((ddrb & 0x80) == 0 && _keyboard.joystickRight) pins_irb |= 0x80;
        break;
    }

    return super.read(regnum);
  }
  
  void cycleDown() {
    if (_config.tapePlay) ca1 = !_tapeDrive.readTapeBit();
    super.cycleDown();
  }
}