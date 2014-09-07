/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

/**
 * Converts binary encoded as string back to a binary array.
 */
List<int> sinToBin(String sinData) {
  const String bincodes = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.!";
  
  int value = 0, bitCount = 0;
  List<int> binaryData = [];
  for (var i = 0; i < sinData.length; i++) {
    value += bincodes.indexOf(sinData[i]) << bitCount;
    if ((bitCount+=6) >= 8) {
      binaryData.add(value & 255);
      bitCount -= 8;
      value >>= 8;
    }
  }
  return binaryData;
}

/**
 * Converts a segment of binary to string. 
 */
String bin2String(List<int> array, int start, int length) {
  return new String.fromCharCodes(array.sublist(start, start+length));
}
