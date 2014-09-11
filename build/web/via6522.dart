/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

/**
 * Base implementation of a 6522 VIA.
 */
class Via6522 {

  // ============================================================
  // Constants
  // ============================================================

  static const int ORA = 1, DDRA = 3, SR = 10;
  
  // ============================================================
  // Attributes
  // ============================================================

  final int startAddress;
  final String vianame;

  final Uint8ClampedList registers = new Uint8ClampedList(16);
  
  int t1c, t1l, t2l_l, t2c;

  bool hasPreCycled;
  bool inhibitT1Interrupt, inhibitT2Interrupt, acrTimedCountdown;
  bool ca2, lastca1, cb1, cb2;
  bool ca1, newca1, newca2;
  int pins_ira, pins_irb;
  
  bool hasInterrupt;
  
  // ============================================================
  // Constructors
  // ============================================================
  
  Via6522(this.startAddress, this.vianame) {
    print("Init VIA at ${startAddress.toRadixString(16)}");
    reset();
  }
  
  // ============================================================
  // Methods
  // ============================================================
  
  /**
   * Reset the VIAs state.
   */
  void reset() {
    print("${vianame} reset");
    
    registers
      ..fillRange(0, registers.length, 0)
      ..fillRange(4, 10, 0xFF);
    
    t1l = t1c = t2c = 0xFFFF;
    t2l_l = 0xFF;
    
    inhibitT1Interrupt = inhibitT2Interrupt = true;
    
    pins_ira = pins_irb  = 0;
    ca1 = lastca1 = newca1 = true;
    ca2 = newca2 = true;
    cb1 = cb2 = false;
    acrTimedCountdown = true;
    hasInterrupt = false;
    
    hasPreCycled=false;
  }
  
  /**
   * Handle a clock cycle on the VIA.
   */
  void cycleUp() {
    // raise interrupts
    if (t1c==-1) {
      if (!inhibitT1Interrupt) {
        registers[13  /*IFR*/] |= 0x40; // Set interrupt flag
        inhibitT1Interrupt = true;
      }
    }
    
    if (t2c==-1) {
      if (acrTimedCountdown && !inhibitT2Interrupt) {
        registers[13  /*IFR*/] |= 0x20; // Set interrupt flag
        inhibitT2Interrupt = true;
      }
    }
    
    if ((registers[12] & 1)!=0) {
      if (ca1!=lastca1) {

        lastca1=ca1;
        if (ca1 != ((registers[12  /*PCR*/]&1)!=0)) { // CA1 control
          registers[13] |= 2;
        }
        
      }
    }
    
    hasInterrupt = (registers[14  /*IER*/] & registers[13  /*IFR*/] & 0x7F) != 0;
  }
  
  void cycleDown() {
    if (hasPreCycled) {
      hasPreCycled=false;
      return;
    }
    
    if (t1c--==-1) {
      // continuous interrupt
      if ((registers[11 /*ACR*/] & 0x40)!=0) {
        t1c = t1l;
        inhibitT1Interrupt = false;
      }
      // one-shot
      else {
        t1c = 0xFFFE;
      }
    }
    
    if (t2c--==-1) {
      t2c = 0xFFFE;
    }
    
    if (((~registers[12]) & 1)!=0) {
      if (ca1!=lastca1) {
        lastca1=ca1;
        if (!ca1) {
          registers[13] |= 2; // IFR
        }
      }
    }
  }
  
  int read(int regnum) {
    regnum &= 0xF;

    switch (regnum) {
    case 0 /*IRB*/: 
      int ddrb = registers[2  /*DDRB*/]; // 0 in 2  /*DDRB*/ is input
      int pins_in = (~pins_irb) & (~ddrb);
      int reg_in = registers[0  /*ORB*/] & ddrb;
      return (pins_in | reg_in) & 0xFF;
    
    // Read of input register A, depends wholly on what's going on on the
    // pins
    case 1 /*IRA*/:
      // Clear ca1,ca2 interrupt flags, only if not "independent"
      int ic = (registers[12  /*PCR*/] >> 1) & 7;
      registers[13  /*IFR*/] &= (ic != 1 && ic != 3) ? ~3 : ~1;
      return (~pins_ira) & (~registers[DDRA]) & 0xFF; // 0 in DDRA is input //

    case 15 /*IRA_nohs*/:
    
      // TODO why was this here?
      //if (this==vic20.via2) return (~pins_ira) & (~reg[DDRA]) & 0xFE;
      return (~pins_ira) & (~registers[DDRA]) & 0xFF; // 0 in DDRA is input //
      // Might need to remove
      // data direction reg
      // 0 /*IRB*/ works differently, it will read what's on the pins for
      // inputs, but what's in the register for outputs
    case 4/*T1C_L*/: 
      // reset interrupt flag
      registers[13  /*IFR*/] &= ~0x40;
      inhibitT1Interrupt = false;
      return t1c&0xFF;
      // return reg[regnum];
    
    case 5/*T1C_H*/: 
      return (t1c>>8)&0xFF;
    
    case 6/*T1L_L*/: 
      return t1l&0xFF;
    
    case 7/*T1L_H*/: 
      return (t1l>>8)&0xFF;
    
    case 8 /* T2C_L */: 
      // reset interrupt flag
      registers[13  /*IFR*/] &= ~0x20;
      inhibitT2Interrupt = false;
      return t2c & 0xFF;
      // return reg[regnum];
    
    case 9 /* T2C_H */: 
      return (t2c>>8)&0xFF;
    
    // Interrupt flag register
    case 13  /*IFR*/: 
      var result = registers[13  /*IFR*/] & 0x7F;
      // If any flag set top bit must be set
      return (result!=0)?(result|0x80):result;
    
    case 14  /*IER*/:
      // interrupt enable register
      return registers[14  /*IER*/] | 0x80;
    default:
      return registers[regnum];
    }
  }

  void invisibleWrite(int regnum, int value) {
    registers[regnum] = value;
  }
  
  int invisibleRead(int regnum) {
    regnum&=15;
    switch(regnum) {
      case 4/*T1C_L*/: 
        return t1c&0xFF;
      
      case 5/*T1C_H*/: 
        return (t1c>>8)&0xFF;
      
      case 6/*T1L_L*/: 
        return t1l&0xFF;
      
      case 7/*T1L_H*/: 
        return (t1l>>8)&0xFF;
      
      case 8 /* T2C_L */: 
        return t2c & 0xFF;
        // return reg[regnum];
      
      case 9 /* T2C_H */: 
        return (t2c>>8)&0xFF;
      
      case 15 /* T2C_H */: 
        return registers[1];
      
      default:
        return registers[regnum];
    }
  }
  
  /**
   * {@inheritDoc}
   * 
   * TODO Writes aren't latched immediately?
   */
  void write(int regnum, int value) {
  //console.debug(vianame,"w",regnum&15,value);
    cycleDown();
    hasPreCycled=true;
    
    switch(regnum&15) {
    // ORB
    case 0:
      registers[0] = value;
      break;
    //var ORA = 1;
    //var 1 /*IRA*/ = 1;
    case 1:
      var ic = (registers[12  /*PCR*/] >> 1) & 7;
      registers[13  /*IFR*/] &= (ic != 1 && ic != 3) ? ~3 : ~1;
      registers[ORA] = value;
      break;
      
    case 15:
      registers[ORA] = value;
      break;
    
    case 2: registers[2] = value; break;
    case 3: registers[3] = value; break;
    
    // var 4/*T1C_L*/ = 4;
    case 4:
      t1l = (t1l&~0xFF) | value;
      // reg[6  /*T1L_L*/] = value;
      break;
    // var 5 /*T1C_H*/ = 5;
    case 5:
      value<<=8;
      t1l = (t1l&0xFF)|value;
      t1c = t1l;
      //reg[7  /*T1L_H*/] = reg[5 /*T1C_H*/] = value;
      // reg[4/*T1C_L*/] = reg[6  /*T1L_L*/];
      // reset interrupt flag
      registers[13  /*IFR*/] &= ~0x40; // flag not to be reset until next cycle?
      inhibitT1Interrupt = false;
      break;
    // T1L_L
    case 6:
      t1l = (t1l&0xFF00) | value;
      break;
    // var 7  /*T1L_H*/ = 7;
    case 7:
      value<<=8;
      t1l = (t1l&0xFF)|value;
      // reg[7  /*T1L_H*/] = value;
      registers[13  /*IFR*/] &= ~0x40; // flag not to be reset until next cycle?
      break;
    // var 8 /* T2C_L */ = 8;
    case 8:
      t2l_l = value;
      break;
      
    // var 9  /*T2C_H*/ = 9;
    case 9:
      t2c = (value<<8) | t2l_l;
      //reg[9 /*T2C_H*/] = value;
      //reg[8 /* T2C_L */] = t2l_l;
      // reset interrupt flag
      registers[13  /*IFR*/] &= ~0x20;
      inhibitT2Interrupt = false;
      break;
    
    case 10: registers[10] = value; break;
    case 11: registers[11] = value; acrTimedCountdown = (registers[11 /*ACR*/] & 0x20)==0; break;
    case 12: registers[12] = value; break;
    
    // var 13  /*IFR*/ = 13;
    case 13:
      registers[13  /*IFR*/] &= ~value;
      break;
    
    // var 14  /*IER*/ = 14;
    case 14:
      if ((value & 0x80)!=0) {
        registers[14  /*IER*/] |= value;
      } else {
        registers[14  /*IER*/] &= ~value;
      }
      break;
    // var 15 /*ORA_nohs*/ = 15;
    // var 15 /*IRA_nohs*/ = 15;
    default:
      registers[1 /*ORA*/] = value;
      break;
    }
  }
}
