/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

class Cpu6502 {

  static const int N = 1 << 7, V = 1 << 6, R = 1 << 5, B = 1 << 4, D = 1 << 3, I = 1 << 2, Z = 1 << 1, C = 1;
  final Vic20 _bus;
  
  Cpu6502(this._bus) {
    _INST_RESET = [nullOp, nullOp, loadPCResetL, loadPCResetH, nextInst];
    _INST_IRQ = [nullOp, nullOp, pushPcH, pushPcL, pushPsetI, loadPCInterruptL, loadPCInterruptH, nextInst ];

    _INST_NMI = [nullOp, nullOp, pushPcH, pushPcL, pushPsetI, loadPCNmiL, loadPCNmiH, nextInst];

    _INST_BAD = [badInst, halt];

    _INST_JAM = [jamInst, halt];

    /*
     * BRK 2 | PBR,PC+1 | Signature | R 3 | 0,S | Program Counter High | W 4 |
     * 0,S-1 | Program Counter Low | W 5 | 0,S-2 | (COP Latches)P | W 6 | 0,VA |
     * Abs.Addr. Vector Low | R 7 | 0,VA+1 | Abs.Addr. Vector High | R
     * >> DONE
     */
    _BRK = [pcNull, pushPcH, pushPcL, pushPorBsetI, loadPCInterruptL, loadPCInterruptH, nextInst];

    /*
     * e.g. ORA ($FF,x)
     * OK
     */
    // FINE
    _INST_X_IND = [
                      // 2 | PBR,PC+1   | Direct Offset         | R
                      zp_x_from_pc,
                      // 3 | PBR,PC+1   | Internal Operation    | R
                      nullOp,
                      // 4 | 0,D+DO+X   | Absolute Address Low  | R
                      load_offset_zp_l,
                      // 5 | 0,D+DO+X+1 | Absolute Address High | R
                      load_offset_zp_h,
                      // 6 | DBR,AA     | Data Low              | R/W
                      op_offset,
                      //
                      nextInst];
    
    // ?
    _INST_X_IND_RMW = [ zp_x_from_pc, nullOp,
                           load_offset_zp_l, load_offset_zp_h, op_offset_rmw, nullOp // TODO
                           // this
                           // should
                           // be an
                           // old
                           // data
                           // write
                           , op_offset_w, nextInst ];
    
    // FINE
    _INST_X_IND_W = [
                        // 2   |  PBR,PC+1        | Direct Offset         |    R
                        zp_x_from_pc,
                        // 3   |  PBR,PC+1        | Internal Operation    |    R
                        nullOp,
                        // 4   |  0,D+DO+X        | Absolute Address Low  |    R
                        load_offset_zp_l,
                        // 5   |  0,D+DO+X+1      | Absolute Address High |    R 
                        load_offset_zp_h,
                        // 6   |  DBR,AA          | Data Low              |   R/W
                        op_offset_w,
                        nextInst];

    /*
     * DCP ($FF,x)
     */
    _INST_X_IND_I = [
                        // 2 | PBR,PC+1 | Direct Offset | R
                        zp_x_from_pc,
                        // 3 | PBR,PC+1 | Internal Operation | R
                        nullOp,
                        // 4 | 0,D+DO+X | Absolute Address Low | R
                        load_offset_zp_l,
                        // 5 | 0,D+DO+X+1 | Absolute Address High | R
                        load_offset_zp_h,
                        // 6 | DBR,AA | Data Low | R 
                        op_offset,
                        // 7 | DBR,AA | Old Data Low | W
                        nullOp,
                        // 8 | DBR,AA | New Data Low | W
                        op_offset_w,
                        nextInst];
    
    // Illegal instructions
    _INST_Y_IND_I = [zp_y_from_pc, nullOp,
                        load_offset_zp_l, load_offset_zp_h, op_offset, nullOp, op_offset_w,
                        nextInst];

    /*
     * e.g. ORA ($FF),Y
     */
    // FINE
    _INST_IND_Y = [
                      // 2 | PBR,PC+1 | Direct Offset | R
                      zp_from_pc,
                      // 3 | 0,D+DO | Absolute Address Low | R
                      load_offset_zp_l,
                      // 4 | 0,D+DO+1 | Absolute Address High | R
                      load_offset_zp_h_plus_y,
                      // 4a | DBR,AAH,AAL+YL | Internal Operation | R
                      // Add 1 cycle for indexing across page boundaries, or write
                      nullOp,
                      // 5 | DBR,AA+Y | Data Low | R/W 
                      op_offset,
                      nextInst];
    
    // illegal instructions
    _INST_IND_Y_RMW = [zp_from_pc, load_offset_zp_l,
                          load_offset_zp_h_plus_y, nullOp, op_offset_rmw, nullOp // TODO add
                          // write
                          // back old
                          // data low
                          , op_offset_w, nextInst ];
    
    /*
    STA (z), y
  */
  _INST_IND_Y_W = [
    // 2   |  PBR,PC+1        | Direct Offset         |    R 
    zp_from_pc,
    // 3   |  0,D+DO          | Absolute Address Low  |    R
    load_offset_zp_l,
    // 4   |  0,D+DO+1        | Absolute Address High |    R
    load_offset_zp_h,
    // Add 1 cycle for indexing across page boundaries, or write
    // (4) 4a  |  DBR,AAH,AAL+YL  | Internal Operation    |    R   
    // This is specific to STA (z),y which is a write, so there will always be one extra cycle
    offset_plus_y_w,
    // 5   |  DBR,AA+Y        | Data Low              |   R/W
    op_offset_w, nextInst];

  /*
   * BPL *-2 
   * (5) Add 1 cycle if branch is taken.
   * (6) Add 1 cycle if branch is taken across page boundaries 
   */
   // FINE
  _INST_BCOND = [
    // 2 | PBR,PC+1 | Offset | R (5) 
    b_offset_cond_from_pc,
    // (5) 2a | PBR,PC+2 | Internal Operation | R
    bra_diff_page,
    // (6) 2b | PBR,PC+2+OFF | Internal Operation | R
    nullOp, nextInst];

  /*
   * JSR $FFFF 
   */
  // FINE
  _INST_JSR = [
    // 2 | PBR,PC+1 | NEW PCL | R | 
    zp_from_pc,
    // 3 | 0,S | Internal Operation | R |
    nullOp,
    // 4 | 0,S | Program Counter High | W |
    pushPcH,
    // 5 | 0,S-1 | Program Counter Low | W
    pushPcL,
    // 6 | PBR,PC+2 | NEW PCH | R
    pc_from_zp_and_pc,
    nextInst];

  /*
   * RTI 2 | PBR,PC+1 | Internal Operation | R | 3 | PBR,PC+1 | Internal
   * Operation | R | 4 | 0,S+1 | Status Register | R | 5 | 0,S+2 | New PCL | R
   * | 6 | 0,S+3 | New PCH | R |
   */
   // FINE
  _INST_RTI = [nullOp, nullOp, plp, popPcL, popPcH,
        nextInst];

  /*
   * RTS 2 | PBR,PC+1 | Internal Operation | R 3 | PBR,PC+1 | Internal
   * Operation | R 4 | 0,S+1 | New PCL-1 | R 5 | 0,S+2 | New PCH | R 6 | 0,S+2
   * | Internal Operation | R
   */
  // FINE
  _INST_RTS = [nullOp, nullOp, popPcL, popPcHaddOne,
        nullOp, nextInst];

  // FINE
  _INST_LOGIC_IMM = [logic_imm, nextInst];

  _INST_LOGIC_IMM_SBX = [logic_imm_sbx, nextInst];
  
  /*
   * LDA $FF 2 | PBR,PC+1 | Direct Offset | R | 3 | 0,D+DO | Data Low | R/W |
   */
  _INST_ZPG = [
  // 2   |  PBR,PC+1        | Direct Offset         |    R
  zp_from_pc,
  //  3   |  0,D+DO          | Data Low              |   R/W
  logic_zp,
  nextInst];
  _INST_ZPG_W = [zp_from_pc, logic_zp_w, nextInst];

  /*
   * LDA $FF,X 2
   */
  _INST_ZPG_X = [
    // 2   |  PBR,PC+1        | Direct Offset         |    R
    zp_x_from_pc,
    //  3   |  PBR,PC+1        | Internal Operation    |    R 
    logic_zp,
    // 4   |  0,D+DO+I        | Data Low              |   R/W
    // Need to do the read so the VIAs reset if it happens to be reading the VIA
    nullOp,
    nextInst];
  _INST_ZPG_Y = [
    //  2   |  PBR,PC+1        | Direct Offset         |    R
    zp_y_from_pc,
    // 3   |  PBR,PC+1        | Internal Operation    |    R 
    //nullOp, FIXME
    // 4   |  0,D+DO+I        | Data Low              |   R/W 
    logic_zp,
    nextInst];
  _INST_ZPG_X_W = [zp_x_from_pc, nullOp, logic_zp_w, nextInst];
  _INST_ZPG_Y_W = [zp_y_from_pc, nullOp, logic_zp_w, nextInst];

  /*
   * ASL $FF
   */
  _INST_ZPGs = [
    // 2 | PBR,PC+1 | Direct Offset | R
    zp_from_pc,
    // 3 | 0,D+DO | Data Low | R 
    logic_zp,
    // 4 | 0,D+DO+1 | Internal Operation | R 
    // TODO unmodified data written back
    nullOp,
    // 5 | 0,D+DO | Data Low | W 
    temp_to_zp,
    // 
    nextInst ];

  /*
   * ASL $FF,X 2 | PBR,PC+1 | Direct Offset | R 3 | PBR,PC+1 | Internal
   * Operation | R 4 | 0,D+DO+X | Data Low | R (12)5 | 0,D+DO+X+1 | Internal
   * Operation | R 6 | 0,D+DO+X | Data Low | W (12) Unmodified Data Low is
   * written back to bus in 6502 emulation mode (E=1).
   */
  _INST_ZPGs_X = [zp_x_from_pc, nullOp, logic_zp,
        nullOp // TODO unmod writeback
        , temp_to_zp, nextInst  ];

  /*
   * PHP 2 | PBR,PC+1 | Internal Operation | R 3 | 0,S-1 | Register Low | W
   */
  _INST_PUSH_P = [nullOp, pushP, nextInst];
  _INST_PHA = [nullOp, pushA, nextInst];

  /*
   * PLP 2 | PBR,PC+1 | Internal Operation | R 3 | PBR,PC+1 | Internal
   * Operation | R 4 | 0,S+1 | Register Low | R
   */
  _INST_PLP = [nullOp, nullOp, plp, nextInst];
  _INST_PLA = [nullOp, nullOp, pla, nextInst];

  /*
   * CLC 2 | PBR,PC+1 | Internal Operation | R
   */
  _INST_FLAG_CLC = [ clc, nextInst ];
  _INST_FLAG_SEC = [ sec, nextInst ];
  _INST_FLAG_CLI = [ cli, nextInst ];
  _INST_FLAG_SEI = [ sei, nextInst ];
  _INST_FLAG_CLV = [ clv, nextInst ];
  _INST_FLAG_CLD = [ cld, nextInst ];
  _INST_FLAG_SED = [ sed, nextInst ];

  _INST_DEY = [dey, nextInst];
  _INST_DEX = [dex, nextInst];

  _INST_INY = [iny, nextInst];
  _INST_INX = [inx, nextInst];

  _INST_TYA = [tya, nextInst];
  _INST_TAY = [tay, nextInst];

  _INST_TXA = [txa, nextInst];
  _INST_TAX = [tax, nextInst];

  _INST_TXS = [_txs, nextInst];
  _INST_TSX = [tsx, nextInst];

  /*
   * ORA $FFFF,y 2 | PBR,PC+1 | Absolute Address Low | R 3 | PBR,PC+2 |
   * Absolute Address High | R (4) 3a | DBR,AAH,AAL+IL | Internal Operation |
   * R 4 | DBR,AA+I | Data Low | R/W (4) Add 1 cycle for indexing across page
   * boundaries, or write.
   */
  _INST_LOGIC_ABS_Y = [load_offset_abs_l,
        load_offset_abs_h_plus_y, nullOp, op_offset, nextInst];
  _INST_LOGIC_ABS_Y_RMW = [ load_offset_abs_l,
        load_offset_abs_h, offset_plus_y, op_offset_rmw, nullOp// TODO unmod
        // writeback
        , op_offset_w, nextInst ];
  _INST_LOGIC_ABS_Y_W = [ load_offset_abs_l,
        load_offset_abs_h, offset_plus_y_w, op_offset_w, nextInst];

  /*
   * ASL A 2 | PBR,PC+1 | Internal Operation | R
   */
  _INST_OP_A = [opa, nextInst];

  /*
   * NOP 2 | PBR,PC+1 | Internal Operation | R
   */
  _INST_NOP = [nullOp, nextInst];

  /*
   * ORA abs 2 | PBR,PC+1 | Absolute Address Low | R 3 | PBR,PC+2 | Absolute
   * Address High | R 4 | DBR,AA | Data Low | R/W
   */
  _INST_ABS = [ load_offset_abs_l, load_offset_abs_h,
        op_offset, nextInst ];
  // Correct
  _INST_ABS_W = [load_offset_abs_l,
        load_offset_abs_h, op_offset_w, nextInst];

  /*
   * JMP $FFFF 2 | PBR,PC+1 | NEW PCL | R 3 | PBR,PC+2 | NEW PCH | R
   */
  _INST_JMP = [load_pc_abs_l, load_pc_abs_h, nextInst];

  /*
   * JMP ($FFFF) 2 | PBR,PC+1 | Absolute Address Low | R 3 | PBR,PC+2 |
   * Absolute Address High | R 4 | 0,AA | NEW PCL | R 5 | 0,AA+1 | NEW PCH | R
   */
  _INST_JMP_IND = [load_offset_abs_l,
        load_offset_abs_h, load_pc_offset_l, load_pc_offset_h, nextInst];

  /*
   * ORA $FFFF,X 2 | PBR,PC+1 | Absolute Address Low | R 3 | PBR,PC+2 |
   * Absolute Address High | R (4) 3a | DBR,AAH,AAL+IL | Internal Operation |
   * R 4 | DBR,AA+I | Data Low | R/W (4) Add 1 cycle for indexing across page
   * boundaries, or write.
   */
  _INST_ABS_X = [load_offset_abs_l,
        load_offset_abs_h, op_offset_plus_x, op_offset, nextInst];
  _INST_ABS_Y = [load_offset_abs_l,
        load_offset_abs_h, op_offset_plus_y, op_offset, nextInst];
  _INST_ABS_X_W = [load_offset_abs_l,
        load_offset_abs_h, offset_plus_x_w, op_offset_w, nextInst];

  /*
   * LSR $FFFF 2 | PBR,PC+1 | Absolute Address Low | R 3 | PBR,PC+2 | Absolute
   * Address High | R 4 | DBR,AA | Data Low | R 5 | DBR,AA+2 | Internal
   * Operation | R 6 | DBR,AA | Data Low | W
   */
  _INST_ABSs = [load_offset_abs_l, load_offset_abs_h,
        op_offset, nullOp // TODO unmod data writeback
        , temp_to_offset, nextInst];

  /*
   * ASL $FFFF,X 2 | PBR,PC+1 | Absolute Address Low | R 3 | PBR,PC+2 |
   * Absolute Address High | R 4 | DBR,AAH,AAL+XL | Internal Operation | R 5 |
   * DBR,AA+X | Data Low | R 6 | DBR,AA+X+1 | Internal Operation | R 7 |
   * DBR,AA+X | Data Low | W
   */

  _INST_ABS_Xs = [load_offset_abs_l,
        load_offset_abs_h, offset_plus_x_w, op_offset, nullOp // TODO unmod
        // writeback
        , temp_to_offset, nextInst];
  _INST_ABS_Ys = [load_offset_abs_l,
        load_offset_abs_h, offset_plus_y_w, op_offset, nullOp,
        temp_to_offset, nextInst];

  instructionFunctions = [_BRK, // 00
              _INST_X_IND, // ORA (z,x)
              _INST_JAM, // JAM i
              _INST_X_IND_RMW, // SLO (z,x)
              _INST_ZPG, // NOP z
              _INST_ZPG, // ORA z
              _INST_ZPGs, // ASL z
              _INST_ZPGs, // SLO z
              _INST_PUSH_P, // 08 - PHP
              _INST_LOGIC_IMM, // ORA #
              _INST_OP_A, // ASL A
              _INST_LOGIC_IMM, // ANC #
              _INST_ABS, // NOP a
              _INST_ABS, // ORA a
              _INST_ABSs, // ASL a
              _INST_ABSs, // SLO a
              _INST_BCOND, // 10 - BPL r
              _INST_IND_Y, // ORA (z),y
              _INST_JAM, // JAM i
              _INST_IND_Y_RMW, // SLO (z),y
              _INST_ZPG_X, // NOP z,x
              _INST_ZPG_X, // ORA z,x
              _INST_ZPGs_X, // ASL z,x
              _INST_ZPGs_X, // SLO z,x
              _INST_FLAG_CLC, // 18 - CLC
              _INST_LOGIC_ABS_Y, // ORA a,y
              _INST_NOP, // NOP i
              _INST_LOGIC_ABS_Y_RMW, // SLO a,y
              _INST_ABS_X, // NOP a,x
              _INST_ABS_X, // ORA a,x
              _INST_ABS_Xs, // ASL a,x
              _INST_ABS_Xs, // SLO a,x
              _INST_JSR, // 20 - JSR a
              _INST_X_IND, // AND (z,x)
              _INST_JAM, // JAM i
              _INST_X_IND_RMW, // RLA (z,x)
              _INST_ZPG, // BIT z
              _INST_ZPG, // AND z
              _INST_ZPGs, // ROL z
              _INST_ZPGs, // RLA z
              _INST_PLP, // 28 - PLP s
              _INST_LOGIC_IMM, // AND #
              _INST_OP_A, // ROL A
              _INST_LOGIC_IMM, // ANC #
              _INST_ABS, // BIT a
              _INST_ABS, // AND a
              _INST_ABSs, // ROL a
              _INST_ABSs, // RLA a
              _INST_BCOND, // 30 - BMI r
              _INST_IND_Y, // AND (z),y
              _INST_JAM, // JAM i
              _INST_IND_Y_RMW, // RLA (z), y
              _INST_ZPG_X, // NOP z,x
              _INST_ZPG_X, // AND z,x
              _INST_ZPGs_X,// ROL z,x
              _INST_ZPGs_X,// RLA z,x
              _INST_FLAG_SEC, // 38 - SEC
              _INST_LOGIC_ABS_Y, // AND a,y
              _INST_NOP, // NOP i
              _INST_LOGIC_ABS_Y_RMW, // RLA a,y
              _INST_ABS_X, // NOP a,x
              _INST_ABS_X, // AND a,x
              _INST_ABS_Xs, // ROL a,x
              _INST_ABS_Xs, // RLA a,X
              _INST_RTI, // 40 - RTI s
              _INST_X_IND, // EOR (z,x)
              _INST_JAM, // JAM i
              _INST_X_IND_RMW, // SRE (z,x)
              _INST_ZPG, // NOP z
              _INST_ZPG, // EOR z
              _INST_ZPGs, // LSR z
              _INST_ZPGs, // SRE z
              _INST_PHA, // 48 - PHA
              _INST_LOGIC_IMM, // EOR #
              _INST_OP_A, // LSR A
              _INST_LOGIC_IMM, // ASR #
              _INST_JMP, // JMP a
              _INST_ABS, // EOR a
              _INST_ABSs, // LSR a
              _INST_ABSs, // SRE a
              _INST_BCOND, // 50 - BVC r
              _INST_IND_Y, // EOR (z),y
              _INST_JAM, // JAM i
              _INST_IND_Y_RMW, // SRE (z),y
              _INST_ZPG_X, // NOP z,x
              _INST_ZPG_X, // EOR z,x
              _INST_ZPGs_X, // LSR z,x
              _INST_ZPGs_X, // SRE z,x
              _INST_FLAG_CLI, // 58 - CLI
              _INST_LOGIC_ABS_Y, // EOR a,y
              _INST_NOP, // NOP i
              _INST_LOGIC_ABS_Y_RMW, // SRE a,y
              _INST_ABS_X, // NOP a,x
              _INST_ABS_X, // EOR a,x
              _INST_ABS_Xs, // LSR a,x
              _INST_ABS_Xs, // SRE a,x
              _INST_RTS, // 60 - RTS
              _INST_X_IND, // ADC (z,x)
              _INST_JAM, // JAM i
              _INST_X_IND_RMW, // RRA (z,x)
              _INST_ZPG, // NOP z
              _INST_ZPG, // ADC z
              _INST_ZPGs, // ROR z
              _INST_ZPGs, // RRA z
              _INST_PLA, // 68 - PLA
              _INST_LOGIC_IMM, // ADC #
              _INST_OP_A, // ROR A
              _INST_LOGIC_IMM, // ARR #
              _INST_JMP_IND, // JMP (a)
              _INST_ABS, // ADC a
              _INST_ABSs, // ROR a
              _INST_ABSs, // RRA a
              _INST_BCOND, // 70 - BVS r
              _INST_IND_Y, // ADC (z),y
              _INST_JAM, // JAM i
              _INST_IND_Y_RMW, // RRA (z), y
              _INST_ZPG_X, // NOP z,x
              _INST_ZPG_X, // ADC z,x
              _INST_ZPGs_X, // ROR z,x
              _INST_ZPGs_X, // RRA z,x
              _INST_FLAG_SEI, // 78 - SEI
              _INST_LOGIC_ABS_Y, // ADC a,y
              _INST_NOP, // NOP i
              _INST_LOGIC_ABS_Y_RMW, // RRA a,y
              _INST_ABS_X, // NOP a,x
              _INST_ABS_X, // ADC a,x
              _INST_ABS_Xs, // ROR a,x
              _INST_ABS_Xs, // RRA a,x
              _INST_LOGIC_IMM, // 80 - NOP #
              _INST_X_IND_W, // STA (z,x)
              _INST_LOGIC_IMM, // NOP #
              _INST_X_IND_W, // SAX (z,x)
              _INST_ZPG_W, // STY z
              _INST_ZPG_W, // STA z
              _INST_ZPG_W, // STX z
              _INST_ZPG_W, // SAX z
              _INST_DEY, // 88 - DEY
              _INST_LOGIC_IMM, // NOP #
              _INST_TXA, // TXA
              _INST_LOGIC_IMM, // ANE #
              _INST_ABS_W, // STY a
              _INST_ABS_W, // STA a
              _INST_ABS_W, // STX a
              _INST_ABS_W, // SAX a
              _INST_BCOND, // 90 - BCC r
              _INST_IND_Y_W, // STA (z),y
              _INST_JAM, // JAM i
              _INST_BAD, // SHA a,x
              _INST_ZPG_X_W, // STY z,x
              _INST_ZPG_X_W, // STA z,x
              _INST_ZPG_Y_W, // STX z,y
              _INST_ZPG_Y_W, // SAX z,y
              _INST_TYA, // 98 - TYA
              _INST_LOGIC_ABS_Y_W, // STA a,y
              _INST_TXS, // TXS
              _INST_BAD, // SHS a,x
              _INST_BAD, // SHY a,y
              _INST_ABS_X_W, // STA a,x
              _INST_BAD, // SHX a,y
              _INST_BAD, // SHA a,y
              _INST_LOGIC_IMM, // A0 - LDY #
              _INST_X_IND, // LDA (z,x)
              _INST_LOGIC_IMM, // LDX #
              _INST_X_IND, // LAX (z,x)
              _INST_ZPG, // LDY z
              _INST_ZPG, // LDA z
              _INST_ZPG, // LDX z
              _INST_ZPG, // LAX z
              _INST_TAY, // A8 - TAY
              _INST_LOGIC_IMM, // LDA #
              _INST_TAX, // TAX
              _INST_LOGIC_IMM, // LXA #
              _INST_ABS, // LDY a
              _INST_ABS, // LDA a
              _INST_ABS, // LDX a
              _INST_ABS, // LAX a
              _INST_BCOND, // B0 - BCS r
              _INST_IND_Y, // LDA (z),y
              _INST_JAM, // JAM i
              _INST_IND_Y, // LAX (z),y
              _INST_ZPG_X, // LDY z,x
              _INST_ZPG_X, // LDA z,x
              _INST_ZPG_Y, // LDX z,y
              _INST_ZPG_Y, // LAX z,y
              _INST_FLAG_CLV, // B8 - CLV
              _INST_LOGIC_ABS_Y, // LDA a,y
              _INST_TSX, // TSX
              _INST_LOGIC_ABS_Y, // LAE a,y
              _INST_ABS_X, // LDY a,x
              _INST_ABS_X, // LDA a,x
              _INST_ABS_Y, // LDX a,y
              _INST_ABS_Y, // LAX a,y
              _INST_LOGIC_IMM, // C0 - CPY #
              _INST_X_IND, // CMP (z,x)
              _INST_LOGIC_IMM, // NOP #
              _INST_X_IND_I, // DCP (z,x)
              _INST_ZPG, // CPY z
              _INST_ZPG, // CMP z
              _INST_ZPGs, // DEC z
              _INST_ZPGs, // DCP z
              _INST_INY, // C8 - INY
              _INST_LOGIC_IMM, // CMP #
              _INST_DEX, // DEX
              _INST_LOGIC_IMM_SBX, // SBX #
              _INST_ABS, // CPY a
              _INST_ABS, // CMP a
              _INST_ABSs, // DEC a
              _INST_ABSs, // DCP a
              _INST_BCOND, // D0 - BNE r
              _INST_IND_Y, // CMP (z),y
              _INST_JAM, // JAM i
              _INST_Y_IND_I, // DCP (z),y
              _INST_ZPG_X, // NOP z,x
              _INST_ZPG_X, // CMP z,x
              _INST_ZPGs_X, // DEC z,x
              _INST_ZPGs_X, // DCP z,x
              _INST_FLAG_CLD, // D8 - CLD
              _INST_LOGIC_ABS_Y, // CMP a,y
              _INST_NOP, // NOP i
              _INST_ABS_Ys, // DCP a,y
              _INST_ABS_X, // NOP a,x
              _INST_ABS_X, // CMP a,x
              _INST_ABS_Xs, // DEC a,x
              _INST_ABS_Xs, // DCP a,x
              _INST_LOGIC_IMM, // E0 - CPX #
              _INST_X_IND, // SBC (z,x)
              _INST_LOGIC_IMM, // NOP #
              _INST_X_IND_I, // ISB (z,x)
              _INST_ZPG, // CPX z
              _INST_ZPG, // SBC z
              _INST_ZPGs, // INC z
              _INST_ZPGs,// ISB z
              _INST_INX, // E8 - INX i
              _INST_LOGIC_IMM, // SBC #
              _INST_NOP, // NOP i
              _INST_LOGIC_IMM, // SBC #
              _INST_ABS, // CPX a
              _INST_ABS, // SBC a
              _INST_ABSs, // INC a
              _INST_ABSs, // ISB a
              _INST_BCOND, // F0 - BEQ r
              _INST_IND_Y, // SBC (z),y
              _INST_JAM, // JAM i
              _INST_Y_IND_I, // ISB (z),y
              _INST_ZPG_X, // NOP z,x
              _INST_ZPG_X, // SBC z,x
              _INST_ZPGs_X, // INC z,x
              _INST_ZPGs_X, // ISB z,x
              _INST_FLAG_SED, // F8 - SED
              _INST_LOGIC_ABS_Y, // SBC a,y
              _INST_NOP, // NOP i
              _INST_ABS_Ys, // ISB a,y
              _INST_ABS_X, // NOP a,x
              _INST_ABS_X, // SBC a,x
              _INST_ABS_Xs, // INC a,x
              _INST_ABS_Xs // ISB a,x
              ];
  
    operation = [ null, // 00 BRK
         ora, // ORA (z,x)
         null, // JAM
         slo, // SLO (z,x)
         nullProc, // NOP z
         ora, // ORA z
         asl, // ASL z
         slo, // SLO z
         null, // 08 - BPL r
         ora, // ORA #
         asl, // ASL A
         anc, // ANC #
         nullProc, // NOP a
         ora, // ORA a
         asl, // ASL a
         slo, // SLO a
         null, // 10 - BPL r
         ora, // ORA (z),y
         null, // JAM i
         slo, // SLO (z),y
         nullProc, // NOP z,x
         ora, // ORA z,x
         asl, // ASL z,x
         slo, // SLO z,x
         null, // 18 - CLC
         ora, // ORA a,y
         null, // NOP i
         slo, // SLO a,y
         nullProc, // NOP a,x
         ora, // ORA a,x
         asl, // ASL a,x
         slo, // SLO a,x
         null, // 20 - JSR a
         and, // AND (z,x)
         null, // JAM i
         rla, // RLA (z,x)
         bit, // BIT z
         and, // AND z
         rol, // ROL z
         rla, // RLA z
         null, // 28 - PLP s
         and, // AND #
         rol, // ROL A
         anc, // ANC #
         bit, // BIT a
         and, // AND a
         rol, // ROL a
         rla, // RLA a
         null, // 30 - BMI
         and, // AND (z),y
         null, // JAM i
         rla, // RLA (z), y
         nullProc, // NOP z,x
         and, // AND z,x
         rol, // ROL z,x
         rla, // RLA z,x
         null, // 38 - SEC
         and, // AND a,y
         null, // NOP
         rla, // RLA a,y
         nullProc, // NOP a,x
         and, // AND a,x
         rol, // ROL a,x
         rla, // RLA a,x
         null, // 40 - RTI
         eor, // EOR (z,x)
         null, // JAM i
         sre, // SRE (z,x)
         nullProc, // NOP z,x
         eor, // EOR z,x
         lsr, // LSR z,x
         sre, // SRE z,x
         null, // 48 - PHA
         eor, // EOR #
         lsr, // LSR A
         asr, // ASR #
         null, // JMP a
         eor, // EOR a
         lsr, // LSR a
         sre, // SRE a
         null, // 50 - BVC r
         eor, // EOR (z),y
         null, // JAM i
         sre, // SRE (z),y
         nullProc, // NOP z,x
         eor, // EOR z,x
         lsr, // LSR z,x
         sre, // SRE z,x
         null, // 58 - CLI
         eor, // EOR a,y
         null, // NOP i
         sre, // SRE a,y
         nullProc, // NOP a,x
         eor, // EOR a,x
         lsr, // LSR a,x
         sre, // SRE a,x
         null, // 60 - RTS
         adc, // ADC (z,x)
         null, // JAM i
         rra, // RRA (z,x)
         nullProc, // NOP z
         adc, // ADC z
         ror, // ROR z
         rra, // RRA z
         null, // 68
         adc, // ADC #
         ror, // ROR a
         arr, // ARR #
         null, // JMP (a)
         adc, // ADC a
         ror, // ROR a
         rra, // RRA a
         null, // 70 - BVS r
         adc, // ADC (z),y
         null, // JAM i
         rra, // RRA (z),y
         nullProc, // NOP z,x
         adc, // ADC z,x
         ror, // ROR z,x
         rra, // RRA z,x
         null, // 78 - SEI
         adc, // ADC a,y
         null, // NOP i
         rra, // RRA a,y
         nullProc, // NOP a,x
         adc, // ADC a,x
         ror, // ROR a,x
         rra, // RRA a,x
         nullProc, // 80 - NOP #
         sta, // STA (z,x)
         nullProc, // NOP #
         sax, // SAX (z,x)
         sty, // STY z
         sta, // STA z
         stx, // STX z
         sax, // SAX z
         null, // 88 - DEY i
         nullProc, // NOP #
         null, // TXA
         ane, // ANE #
         sty, // STY a
         sta, // STA a
         stx, // STX a
         sax, // SAX a
         null, // 90 - BCC
         sta, // STA (z),y
         null, // JAM i
         null, // SHA a,x
         sty, // STY z,x
         sta, // STA z,x
         stx, // STX z,y
         sax, // SAX z,y
         null, // 98 - TYA
         sta, // STA a,y
         null, // TXS
         null, // SHS a,x
         null, // SHY a,y
         sta, // STA a,x
         null, // SHX a,y
         null, // SHA a,y
         ldy, // A0
         lda, // LDA (z,x)
         ldx, // LDX #
         lax, // LAX (z,x)
         ldy, // LDY a
         lda, // LDA z
         ldx, // LDX z
         lax, // LAX z
         null, // A8 - TAY
         lda, // LDA #
         null, // TAX
         lxa, // LXA
         ldy, // LDY a
         lda, // LDA a
         ldx, // LDX a
         lax, // LAX a
         null, // B0 - CLV
         lda, // LDA (z),y
         null, // JAM i
         lax, // LAX (z),y
         ldy, // LDY z,x
         lda, // LDA z,x
         ldx, // LDX z,y
         lax, // LAX z,y
         null, // B8 - CLV
         lda, // LDA a,y
         null, // TSX
         lae, // LAE a,y
         ldy, // LDY a,x
         lda, // LDA a,x
         ldx, // LDX a,y
         lax, // LAX a,y
         cpy, // C0 - CPY #
         cmp, // CMP (z,x)
         nullProc, // NOP #
         dcp, // DCP (z,x)
         cpy, // CPY z
         cmp, // CMP z
         dec, // DEC z
         dcp, // DCP z
         null, // C8 - INY
         cmp, // CMP #
         null, // DEX i
         null, // SBX #
         cpy, // CPY a
         cmp, // CMP a
         dec, // DEC a
         dcp, // DCP a
         null, // D0 - BNE r
         cmp, // cmp (z),y
         null, // JAM i
         dcp, // DCP (z),y
         nullProc, // NOP z,x
         cmp, // CMP z,x
         dec, // DEC z,x
         dcp, // DCP z,x
         null, // D8 - CLD
         cmp, // CMP a,y
         null, // NOP i
         dcp, // DCP a,y
         nullProc, // NOP a,x
         cmp, // CMP a,x
         dec, // DEC a,x
         dcp, // DCP a,x
         cpx, // E0 - CPX #
         sbc, // SBC (z,x)
         nullProc, // NOP #
         isb, // ISB (z,x)
         cpx, // CPX z
         sbc, // SBC z
         inc, // INC z
         isb, // ISB z
         null, // E8 - INX i
         sbc, // SBC #
         null, // NOP i
         sbc, // SBC #
         cpx, // CPX a
         sbc, // SBC a
         inc, // INC a
         isb, // ISB a
         null, // F0 - BEQ r
         sbc, // SBC (z),y
         null, // JAM i
         isb, // ISB (z),y
         nullProc, // NOP z,x
         sbc, // SBC z,x
         inc, // INC z,x
         isb, // ISB z,x
         null, // F8 - SED
         sbc, // SBC a,y
         null, // NOP i
         isb, // ISB a,y
         nullProc, // NOP a,x
         sbc, // SBC a,x
         inc, // INC a,x
         isb // ISB a,x
         ];
  
    reset();
  }


  List<Function> _INST_RESET, _INST_IRQ, _INST_NMI, _INST_BAD, _INST_JAM, _BRK;
  List<Function> _INST_X_IND, _INST_X_IND_RMW, _INST_X_IND_W, _INST_X_IND_I;
  List<Function> _INST_Y_IND_I, _INST_IND_Y, _INST_IND_Y_RMW, _INST_IND_Y_W;
  List<Function> _INST_BCOND, _INST_JSR, _INST_RTI, _INST_RTS;
  List<Function> _INST_LOGIC_IMM, _INST_LOGIC_IMM_SBX;
  List<Function> _INST_ZPG, _INST_ZPG_W, _INST_ZPG_X, _INST_ZPG_Y, _INST_ZPG_X_W, _INST_ZPG_Y_W, _INST_ZPGs,_INST_ZPGs_X;
  List<Function> _INST_PUSH_P, _INST_PHA, _INST_PLP, _INST_PLA;
  List<Function> _INST_FLAG_CLC, _INST_FLAG_SEC, _INST_FLAG_CLI, _INST_FLAG_SEI, _INST_FLAG_CLV, _INST_FLAG_CLD, _INST_FLAG_SED;
  List<Function> _INST_DEY, _INST_DEX, _INST_INY, _INST_INX;
  List<Function> _INST_TYA, _INST_TAY, _INST_TXA, _INST_TAX, _INST_TXS, _INST_TSX;
  List<Function> _INST_LOGIC_ABS_Y, _INST_LOGIC_ABS_Y_RMW, _INST_LOGIC_ABS_Y_W;
  List<Function> _INST_OP_A;
  List<Function> _INST_NOP;
  List<Function> _INST_ABS, _INST_ABS_W;
  List<Function> _INST_JMP, _INST_JMP_IND;
  List<Function> _INST_ABS_X, _INST_ABS_Y, _INST_ABS_X_W, _INST_ABSs, _INST_ABS_Xs, _INST_ABS_Ys;
  
  // **********************************
  // CPU Registers
  // **********************************
  int pc, sp, a, x, y, p, _np;
  
  List<Function> currentInst;
  int currentInstOffset;
  int instruction;
  int b, offset;
  int prevNmi = 0;

  int _irqBits = 0, _nmiBits = 0;

  void push(int value) {
    (_bus.write)(0x100 + sp, value);
    sp = (sp - 1) & 0xFF;
  }

  int pop() {
    sp = (sp + 1) & 0xFF;
    return (_bus.read)(0x100 + sp);
  }

  void _nz(int value) {
    p &= ~(N|Z);
    p |= (value!=0) ? (value & N) : Z;
  }

  void _nzc(int reg, int value) {
    p &= ~(N|Z|C);
    p |= ((reg -= value)==0) ? Z : reg & N;
    if (reg >= 0)  p |= C;
  }
  
  void nextInst() {    
    int n4 = _nmiBits&4;
    if (n4!=prevNmi && (prevNmi=n4)!=0) {
      currentInst = _INST_NMI;
      currentInstOffset = 0;
    }
    else {
      // Is interrupt and interrupts enabled?
      if ((_irqBits&2)!=0) {
        currentInst = _INST_IRQ;
      } else {
        // Get next instruction
        instruction = (_bus.read)(pc);
        pc = (pc + 1) & 0xFFFF;
        currentInst = instructionFunctions[instruction];
      }
      currentInstOffset = 0;
    }
    
    if (_np!=null) {
      p=_np;
      _np=null;
    }
  }
  
  void badInst() {
    throw "Bad instruction pc=${pc.toRadixString(16)} instruction = $instruction";
    _bus.reset();
  }

  void jamInst() {
    throw "Jam instruction pc=${pc.toRadixString(16)} instruction = $instruction";
    _bus.reset();
  }

  void halt() {
    throw 'Cpu Halted!';
  }

  void nullOp() {
    // empty
  }
  
  void pcNull() {
    // ??
    pc = (pc+1)&0xFFFF;
  }

  void pushA() {
    push(a);
  }

  void pushP() {
    push(p);
  }

  void pushPcH() {
    push(pc >> 8);
  }

  void pushPcL() {
    push(pc & 0xFF);
  }

  void pushPorBsetI() {
    // 5 | 0,S-2 | P | W
    push(p | B);
    p |= I;
  }

  void pushPsetI() {
    // 5 | 0,S-2 | P | W
    push(p);
    p |= I;
  }

  void plp() {
    p = (pop()&~B) | R;
  }

  void pla() {
    _nz(a = pop());
  }

  void popPcL() {
    pc = pop();
  }

  void popPcH() {
    pc |= (pop() << 8);
  }

  void popPcHaddOne() {
    pc = ((pop() << 8) | pc) + 1;
    pc &= 0xFFFF;
  }

  void loadPCResetL() {
    pc = (_bus.read)(0xFFFC);
  }

  void loadPCResetH() {
    pc |= (_bus.read)(0xFFFD) << 8;
  }

  void loadPCInterruptL() {
    pc = (_bus.read)(0xFFFE);
  }

  void loadPCInterruptH() {
    pc |= (_bus.read)(0xFFFF) << 8;
  }
  
  void loadPCNmiL() {
    pc = (_bus.read)(0xFFFA);
  }

  void loadPCNmiH() {
    pc |= (_bus.read)(0xFFFB) << 8;
  }

  // !
  void zp_x_from_pc() {
    offset = ((_bus.read)(pc) + x) & 0xFF;
    pc = (pc + 1) & 0xFFFF;
  }

  // !
  void load_offset_zp_l() {
    b = (_bus.read)(offset++);
  }

  // !
  void load_offset_zp_h() {
    offset = b | ((_bus.read)(offset & 0xFF) << 8);
  }

  void load_offset_zp_h_plus_y() {
    offset = ((b | ((_bus.read)(offset & 0xFF) << 8)) + y)&0xFFFF;
    if ((offset & 0xFF) >= y) {
      // skip cycle if same page
      currentInstOffset++;
    }
  }

  void op_offset() {
    b = (_bus.read)(offset);
    operation[instruction]();
  }

  void op_offset_rmw() {
    b = (_bus.read)(offset);
  }

  void op_offset_w() {
    operation[instruction]();
    (_bus.write)(offset, b);
  }

  void zp_from_pc() {
    offset = (_bus.read)(pc);
    pc = (pc + 1) & 0xFFFF;
  }

  void pc_from_zp_and_pc() {
    pc = ((_bus.read)(pc) << 8) | offset;
  }

  void offset_plus_y() {
    offset = (offset + y) & 0xFFFF;
    if ((offset & 0xFF) >= y) {
      // skip cycle if same page, by calling next instruction directly
      (currentInst[currentInstOffset++])();
    }
  }

  void offset_plus_x() {
    offset = (offset + x) & 0xFFFF;
    if ((offset & 0xFF) >= x) {
      // skip cycle if same page, by calling next instruction directly
      (currentInst[currentInstOffset++])();
    }
  }

  void offset_plus_x_w() {
    offset = (offset + x) & 0xFFFF;
  }

  void offset_plus_y_w() {
    offset = (offset + y) & 0xFFFF;
  }

  void b_offset_cond_from_pc() {
    int diff = (_bus.read)(pc);
    if (diff>127) diff=diff-256;

    int pp = ((instruction & 0x20) != 0) ? (p ^ 0xFF) : p;
    // TODO Z may not work!
    int mask = ((Z << 24) | (C << 16) | (V << 8) | N) /*>*/>> ((instruction >> 6) << 3);
    if ((pp & mask) != 0) {
      pc++;
      // Skip branch
      _irqBits = 0;
      currentInstOffset += 2;
    } else {
      // Take branch
      offset = (pc + (diff) + 1);
    }
  }

  void bra_diff_page() {
    if (((offset ^ pc) >> 8) == 0) {
      currentInstOffset++; // skip extra cycle
    }
    pc = offset;
  }

  void logic_imm() {
    b = (_bus.read)(pc);
    pc = (pc + 1) & 0xFFFF;
    operation[instruction]();
  }
  
  void logic_imm_sbx() {
    x = (x&a) - (_bus.read)(pc);
    if (x<0) p &= ~C; else p |= C;
    _nz(x &= 0xFF);
    
    pc = (pc + 1) & 0xFFFF;
  }

  void logic_zp() {
    b = (_bus.read)(offset);
    operation[instruction]();
  }
  
  void nullread_offset() {
    (_bus.read)(offset);
  }

  void logic_zp_w() {
    operation[instruction]();
    (_bus.write)(offset, b);
  }

  void zp_y_from_pc() {
    offset = ((_bus.read)(pc) + y) & 0xFF;
    pc = (pc + 1) & 0xFFFF;
  }

  void temp_to_zp() {
    (_bus.write)(offset, b);
  }

  void clc() {
    p &= ~C;
  }

  void sec() {
    p |= C;
  }

  void cli() {
    // p &= ~I;
    _np = p & ~I;
  }

  void sei() {
    _np = p | I;
    // p |= I;
  }

  void clv() {
    p &= ~V;
  }

  void cld() {
    p &= ~D;
  }

  void sed() {
    p |= D;
  }

  void dey() {
    _nz(y = (y - 1) & 0xFF);
  }

  void dex() {
    _nz(x = (x - 1) & 0xFF);
  }

  void iny() {
    _nz(y = (y + 1) & 0xFF);
  }

  void inx() {
    _nz(x = (x + 1) & 0xFF);
  }

  void tya() {
    _nz(a = y);
  }

  void tay() {
    _nz(y = a);
  }

  void txa() {
    _nz(a = x);
  }

  void tax() {
    _nz(x = a);
  }

  void _txs() {
    sp = x;
  }


  void tsx() {
    _nz(x = sp);
  }

  void load_offset_abs_l() {
    offset = (_bus.read)(pc);
    pc = (pc + 1) & 0xFFFF;
  }

  void load_offset_abs_h() {
    offset |= ((_bus.read)(pc) << 8);
    pc = (pc + 1) & 0xFFFF;
  }

  void op_offset_plus_x() {
    offset = (offset+x)&0xFFFF;
    if ((offset & 0xFF) >= x) {
      b = (_bus.read)(offset);
      operation[instruction]();
      // skip cycle as same page
      currentInstOffset++;
    }
  }

  void op_offset_plus_y() {
    offset = (offset+y)&0xFFFF;
    if ((offset & 0xFF) >= y) {
      b = (_bus.read)(offset);
      operation[instruction]();
      // skip cycle as same page
      currentInstOffset++;
    }
  }

  void load_offset_abs_h_plus_y() {
    offset = (offset|((_bus.read)(pc) << 8)) + y;
    pc = (pc + 1) & 0xFFFF;
    if ((offset & 0xFF) >= y) {
      // skip cycle if same page, by calling next instruction directly
      currentInstOffset++;
    }
  }

  void opa() {
    b = a;
    operation[instruction]();
    a = b;
  }

  void load_pc_abs_l() {
    b = (_bus.read)(pc);
    pc = (pc + 1) & 0xFFFF;
  }

  void load_pc_abs_h() {
    pc = ((_bus.read)(pc) << 8) | b;
  }

  void load_pc_offset_l() {
    pc = (_bus.read)(offset++);
    if ((offset & 0xFF) == 0) {
      offset -= 0x100;
    }
    offset &= 0xFFFF;
  }

  void load_pc_offset_h() {
    pc |= ((_bus.read)(offset++) << 8);
  }

  void temp_to_offset() {
    (_bus.write)(offset, b);
  }

  void nullProc() {
    // nothing
  }

  void ora() {
    _nz(a |= b);
  }

  void sre() {
    if ((b & C)!=0) {
      p |= C;
    } else {
      p &= ~C;
    }

    b >>= 1;
    _nz(a ^= b);
  }

  void rra() {
    // {adr}:={adr}ror A:=A adc {adr}
    ror();
    adc();
  }

  void rla() {
    // {adr}:={adr}rol A:=A and {adr}
    var oldCarry = p & C;
    p &= ~C;
    p |= (b >> 7);
    b = (b << 1) | oldCarry;
    b &= 0xFF;

    _nz(a &= b);
  }

  void slo() {
    // {adr}:={adr}*2 A:=A or {adr}
    if ((b & N) != 0) {
      p |= C;
    } else {
      p &= ~C;
    }

    b = (b << 1) & 0xFF;
    _nz(a |= b);
  }

  void and() {
    _nz(a &= b);
  }

  void eor() {
    _nz(a ^= b);
  }

  void adc() {
    // decimal mode
    if ((p & D) != 0) {
        int sum = (a & 0xF) + (b & 0xF) + (p & C);
        p &= ~(N | Z | C | V);
        if (sum > 0x09) {
          sum += 0x06;
        }
        if (sum > 0x1F) {
          sum -= 0x10;
        }

        sum += (a & 0xF0) + (b & 0xF0);
        p |= (sum & N);
        p |= ((~(a ^ b) & (a ^ sum)) & N) >> 1; // Overflow
        a = (sum & 0xFF);
        if (a == 0) {
          p |= Z;
        }
        if (sum >= 0xA0) {
          a += 0x60;
          a &= 0xFF;
          p |= C;
        }
      } else {
        int sum2 = a + b + (p & C);
        p &= ~(N | Z | C | V);

        p |= ((~(a ^ b) & (a ^ sum2)) & N) >> 1; // Overflow
        p |= ((sum2 >> 8) & C);
        a =(sum2 & 0xFF);
        if (a == 0) {
          p |= Z;
        }
        p |= (a & N);
      }
  }

  void sbc() {
    if ((p & D) != 0) {
      int sumadd = 0, sum = (a & 0xF) - (b & 0xF) - (~p & C);
      p &= ~(N | Z | C | V);

      if (sum < -10) {
        sumadd = 10;
      } else if (sum < 0) {
        sumadd = -6;
      }

      sum += (a & 0xF0) - (b & 0xF0);
      if ((sum & 0xFF) == 0) {
        p |= Z;
      }
      p |= (sum & N);
      p |= (((a ^ b) & (a ^ sum)) & N) >> 1;
      sum += sumadd;
      if (sum < 0) {
        sum += 0xA0;
      } else {
        if (sum >= 0xA0) {
          sum -= 0x60;
        }
        p |= C;
      }

      a = (sum & 0xFF);
    } else {
      int sum2 = a - b - (~p & C);
      p &= ~(N | Z | C | V);
      p |= (((a ^ b) & (a ^ sum2)) & N) >> 1; // Overflow
      a =  (sum2 & 0xFF);
      p |= ((~sum2 >> 8) & C); // Carry
      p |= (a & N); // Negative
      if (a == 0) {
        p |= Z; // Zero
      }
    }
  }

  void cmp() {
    _nzc(a, b);
  }

  void cpx() {
    _nzc(x, b);
  }

  void cpy() {
    _nzc(y, b);
  }

  void bit() {
    p &= ~(N|V|Z);
    if ((a & b) == 0) p |= Z;
    p |= (b & (N|V));
  }

  void lda() {
    _nz(a = b);
  }

  void ldx() {
    _nz(x = b);
  }

  void ldy() {
    _nz(y = b);
  }

  void sta() {
    b = a;
  }

  void sax() {
    b = a & x;
  }

  void stx() {
    b = x;
  }

  void sty() {
    b = y;
  }

  void asl() {
    p &= ~C;
    p |= (b >> 7);
    _nz(b = (b << 1) & 0xFF);
  }

  void rol() {
    var oldCarry = p & C;
    p &= ~C;
    p |= (b >> 7);
    _nz(b = ((b << 1) | oldCarry) & 0xFF);
  }

  void lsr() {
    p &= ~(C | N | Z);
    p |= (b & C);
    // Shift right & set flags
    if ((b >>= 1) == 0) {
      p |= Z;
    }
  }

  void ror() {
    int newN = (p & C) << 7;
    // Set new carry
    p &= ~(C | N | Z);
    // Set C flag
    p |= (b & C) | newN;
    // Set N flag
    b = ((b >> 1) | newN);
    if (b == 0) {
      p |= Z;
    }
  }

  void anc() {
    _nz(a &= b);
    p &= ~C;
    p |= (a >> 7);
  }

  void ane() {
    a = (a | 0xEE) & x;
    _nz(a &= b);
  }

  void lxa() {
    a = x = ((a|0xEE) & b);
    _nz(a);
  }

  void arr() {
    and();
    ror();
    p &= ~(C | V);
    p |= (b >> 5) & C;
    p |= ((b << 2) | (b << 1)) & V;
  }

  void asr() {
    and();
    lsr();
  }

  void dec() {
    _nz(b = (b - 1) & 0xFF);
  }


  void inc() {
    _nz(b = (b + 1) & 0xFF);
  }

  void dcp() {
    dec();
    cmp();
  }

  void isb() {
    inc();
    sbc();
  }

  void lae() {
    a &= b;
    _nz(x = a);
    sp = x;
  }

  void lax() {
    a = b;
    _nz(x = a);
  }

  // **********************************
  // Methods

  List<List<Function>> instructionFunctions;
  List<Function> operation;

  bool isNextInst() {
    return currentInst[currentInstOffset]==nextInst;
  }
  
  void cycle() {
    (currentInst[currentInstOffset++])();
    _nmiBits = ((_nmiBits << 1) | (_bus.hasNmi()?1:0)) & 0xFF; 
    _irqBits = ((_irqBits << 1) | ((((p & I)!=0) || !_bus.hasIrq())?0:1)) & 0xFF;
  }

  void reset() {
    currentInst = _INST_RESET;
    currentInstOffset = 0;

    prevNmi = _irqBits = _nmiBits = 0;
    a = x = y = sp = pc = b = 0;
    _np = null;
    p = R;
  }
}
 