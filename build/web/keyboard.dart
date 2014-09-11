/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

class Keyboard {
  Config _config;
  Vic20 _vic20;
  Via2 _via2;
  
  // public
  List<int> keysdown = [0,0,0,0,0,0,0,0];
  bool joystickRight = false, joystickLeft = false, joystickUp = false, joystickDown = false, joystickFire = false;

  // not sure public or private
  bool pageup = false;

  Keyboard(this._config, this._vic20) {
    joystickRight = joystickLeft = joystickUp = joystickDown = joystickFire = false;

    //KeyboardEventStream.onKeyDown(document.body).listen(_keydownHandler);
    //KeyboardEventStream.onKeyUp  (document.body).listen(_keyupHandler  );
     
    // create a top-level JavaScript function called myJsonpCallback
      js.context["applyKey"] = (sym,keyup) => applyKey(sym,keyup);
    //});
  }
  
  void _keydownHandler(KeyEvent e) { _applyKey(e, false); }
  void _keyupHandler(KeyEvent e)   { _applyKey(e, true ); }
  
  void _applyKey(KeyEvent e, bool keyup) {
    //e.cancelBubble = true;
    e.preventDefault();
    e.stopImmediatePropagation();
    
    var sym = e.keyCode;
    applyKey(sym, keyup);
  }
  
  void applyKey(int sym, bool keyup) {  
    if (_config.joykeys) {
      switch(sym) {
        case 37: joystickLeft  = !keyup; return;
        case 39: joystickRight = !keyup; return;
        case 38: joystickUp    = !keyup; return;
        case 40: joystickDown  = !keyup; return;
        case 192:
        case 96: joystickFire  = !keyup; return;
      }
    }
    
    // TODO NMI
    if (sym==33) {
      pageup = keyup;
      _via2.ca1 = pageup;
    }
    
    for(var i=0; i<64; i++) {
      var keyrow = _vic20.machineDefinition.keymap[i];
      for(var j=0; j<keyrow.length; j++) {
        if(keyrow[j]==sym) {
          var idx = 7-(i>>3), val = 1<<(i&7);
          if (keyup) keysdown[idx]&=~val; else keysdown[idx]|=val;
        }
      }
    }
    
    switch(keyup?sym:-sym) {
      case  113: keysdown[3]&=~0x02; keysdown[4]&=~0x80; break; // SHIFT // F2
      case -113: keysdown[3]|=0x02;  keysdown[4]|=0x80;  break; // SHIFT // F2
      
      case  115: keysdown[3]&=~0x02; keysdown[5]&=~0x80; break; // SHIFT // F4
      case -115: keysdown[3]|=0x02;  keysdown[5]|=0x80;  break; // SHIFT // F4
      
      case  117: keysdown[3]&=~0x02; keysdown[6]&=~0x80; break; // SHIFT // F6
      case -117: keysdown[3]|=0x02;  keysdown[6]|=0x80;  break; // SHIFT // F6
      
      case  119: keysdown[3]&=~0x02; keysdown[7]&=~0x80; break; // SHIFT // F8
      case -119: keysdown[3]|=0x02;  keysdown[7]|=0x80;  break; // SHIFT // F8
      
      case   37: keysdown[3]&=~0x02; keysdown[2]&=~0x80; break; // SHIFT // Right
      case - 37: keysdown[3]|=0x02;  keysdown[2]|=0x80;  break; // SHIFT // Right
      
      case   38: keysdown[3]&=~0x02; keysdown[3]&=~0x80; break; // SHIFT // Down
      case - 38: keysdown[3]|=0x02;  keysdown[3]|=0x80;  break; // SHIFT // Down
    }
  }
}