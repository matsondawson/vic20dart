/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

 /**
 * Implementation of a 6560 NTSC VIC display chip.
 */
class Vic6560 extends Vic656x {
  
  Vic6560(_config, _machine, _memory) : super(_config, _machine, _memory);
  
  /**
   * Default register values for NTSC VIC.
   */
  List<int> defaultRegisterValues() => const [ 5, 25, 150, 174, 27, 240, 87, 234, 0, 0, 0, 0, 0, 0, 0, 27 ];

  // ============================================================
  // Attributes
  // ============================================================
  
  /**
   * Reset the VIC.
   */
  void reset() { 
    print("VIC6560-NTSC reset");
   
    _VERTICAL_BLANK_LAST_ROW = 7;
    _VISIBLE_SCAN_LINE_CYCLES = 50;
    _HORIZONTAL_BLANK_CYCLES = 15;
    _BLANK_LEFT_CYCLES = 2;
    _TOTAL_SCAN_LINES = 261;
    _SCAN_LINE_DELAY = 32; // -2 later when we fix the offset 2 to the

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

    if (_scanLineCounterDelay-- == 0) {
      if (_scanLine==260) {
        registers[4] = 0;
        registers[3] &= 0x7F;
      } else {      
        registers[4] = (_scanLine + 1) >> 1;
        registers[3] = (registers[3] & 0x7F) | (((_scanLine + 1) & 1) << 7);
      }
    }

    _scanCol++;

    // Left blanking
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
        // Update the scan-line counter
        _scanLineCounterDelay = _SCAN_LINE_DELAY;
      }
    }

    
    if (frameIndex==0) {
      if (_displayColCount < 0 || _displayRowCount < 0) {
        bool startFirstLine = ((registers[1] << 1) == _scanLine)  && ((_HORIZONTAL_BLANK_CYCLES - 4) == _scanCol);
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
        _ch = _memory[_fromVicAddress(_base + _chptr)];
        _col = _nextcol;
        _nextcol = _memory[_fromVicAddress(_colbase + _chptr)];
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
