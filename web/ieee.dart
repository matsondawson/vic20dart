/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

abstract class IeeeDevice {
  void reset();
  bool clk();
  bool atn();
  bool data();
}

class Ieee {
  List<IeeeDevice> _devices = new List<IeeeDevice>();

  bool _lastAtn = true;
  
  void addDevice(device) => _devices.add(device);
  bool removeDevice(device) => _devices.remove(device);
  void reset() {
    _devices.forEach((device) => device.reset());
  }
  bool data()  => _devices.any    ((device) => !device.data());
  bool clk()   => _devices.any    ((device) => !device.clk());
  
  bool atn() {
    bool newAtn = _devices.any((device) => device.atn());
    if (newAtn!=_lastAtn) {
      print("atn ${newAtn}");
      _lastAtn = newAtn;
    }
    return newAtn;
  }
}