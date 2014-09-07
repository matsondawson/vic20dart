/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

 /**
 * Implementation of a 6560/6561 VIC display chip.
 */
class Vic6561 extends Vic656x {
  
  Vic6561(_config, _machine, _memory) : super(_config, _machine, _memory);
  
  /**
   * Default register values for NTSC VIC.
   */
  List<int> defaultRegisterValues() => const [ 12, 38, 150, 174, 73, 240, 0, 0, 255, 255, 0, 0, 0, 0, 0, 27 ];

  // ============================================================
  // Attributes
  // ============================================================
  
  /**
   * Reset the VIC.
   */
  void reset() {
    print("VIC6561-PAL reset");
    
    _VERTICAL_BLANK_LAST_ROW = 27;
    _VISIBLE_SCAN_LINE_CYCLES = 56;
    _HORIZONTAL_BLANK_CYCLES = 15;
    _BLANK_LEFT_CYCLES = 6;
    _TOTAL_SCAN_LINES = 312;
    _SCAN_LINE_DELAY = 0;

    super.reset();
  }
  
  /**
   * Handle 1 clock cycle worth of processing.
   */
  void cycle() {
      //if (_hasPreCycled) {
      //  _hasPreCycled=false;
      //  return;
      //}
      
      // ============================================================
      // VIDEO
      // ============================================================
      _scanCol++;

      if (_isBlanking) {
        if (_scanCol == _HORIZONTAL_BLANK_CYCLES) {
          _isBlanking = false;
        } else if (_scanCol == _HORIZONTAL_BLANK_CYCLES - 8) {
          // -8 function of BLANK_LEFT_CYCLES=6 and precycle=2?
          _displayColCount = -1;
          if (_charLineCount != (1 << _charHeightShift) && (_charLineCount != 16)) {
            _chptr = _resetchptr;
          } else {
            _resetchptr = _chptr;
            _charLineCount = 0;
          }
        }
      } else if (_scanCol == _TOTAL_LINE_CYCLES) {

        if (++_scanLine == _TOTAL_SCAN_LINES) {
          videoBegin();
        } else {
          _displayRowCount--;
          _isBlanking = true;
          _scanCol = 0;
          _charLineCount++;
        }
        registers[4] = _scanLine >> 1;
        registers[3] = (registers[3] & 0x7F) | ((_scanLine & 1) << 7);
      }

      
      if (frameIndex==0) {
        if (_displayColCount < 0 || _displayRowCount < 0) {
          bool startFirstLine = ((registers[1] << 1) == _scanLine) && ((_HORIZONTAL_BLANK_CYCLES - 4) == _scanCol);
          if (startFirstLine) {
            _displayRowCount = ((registers[3] >> 1) & 0x3F) << _charHeightShift;
            _chptr = _resetchptr = _charLineCount = 0;
          }

          bool startFirstCol = (_HORIZONTAL_BLANK_CYCLES + (registers[0] & 0x7f) - _BLANK_LEFT_CYCLES - 2) == _scanCol;
          if (startFirstCol && _displayRowCount > 0) {
            _displayColCount = ((registers[2] & 0x7F) + 1) << 1;
            _precount = 2;
        }
      }

    
      bool stageOne = (_displayColCount & 1) == 0;

      if (stageOne) {
        var addr = _base + _chptr;
        _ch = _memory[_fromVicAddress(addr)];
        addr = _colbase + _chptr;
        _col = _nextcol;
        _nextcol = _memory[_fromVicAddress(addr)];
        _chdata = _nextchdata;
      } else {
        int addr = (_charrom + (_ch << _charHeightShift) + _charLineCount) ;
        _nextchdata = _memory[_fromVicAddress(addr)];

        // Not multi-colour mode and invertColours then invert char line data
        if (((_nextcol | registers[0xf]) & 8)==0) _nextchdata ^= 0xFF;
        _chdata = (_chdata << 4) & 0xFF; 
      }

      if (_scanLine > _VERTICAL_BLANK_LAST_ROW) {
        // Is visible scan line
        if (_displayColCount > 0 && _displayRowCount > 0) {
          if (_precount > 0) {
            _precount--;
            if (!_isBlanking) _screenData[_ptr++] = _borderColour;
          } else if (!_isBlanking) {
            if ((_col & 8)!=0) {
              _multicol[2] = _colourPalette[_col & 7];
              _screenData[_ptr++] = multiColSplitSelect.select(_multicol[(_chdata >> 6) & 3], _multicol[(_chdata >> 4) & 3]);
            } else {
              _screenData[_ptr++] = expandMask4bitsTo4Bytes[_chdata>>4].select(_colourPalette[_col & 7], _backColour);
            }
          }

          if (--_displayColCount > 1 && stageOne) _chptr++;
        } else if (!_isBlanking) {
          // RHS or bottom border
          _screenData[_ptr++] = _borderColour;
        }
      } else {
        // Is still blanking
        if (--_displayColCount > 0 && _displayRowCount > 0) {
          if (stageOne && _displayColCount > 1) _chptr++;
          _precount--;
        }
      }
    }

    if (++_soundDivider>=16) _genAudio();
  }
}
