/**
 * Copyright matsondawson@gmail.com 2013
 */
part of vic20dart;

void fullscreen() {
  if (document.fullscreenElement==null) {
    querySelector("#canvasfs")
        ..requestFullscreen()
        ..style.height = "100%"
        ..style.width  = "100%"
        ..querySelector("canvas").style.height="100%";
  }
  else document.exitFullscreen();
}

void datasetteMouseClick(Vic20 vic20) {
  querySelector('#tapeZoom').style.display='block';
  updateDatasetteView(vic20);
}

void updateDatasetteView(Vic20 vic20) {
  //if (event && event.filepath) {
  //  datasetteMouseClick();
  //}
  querySelector("#datasette_play") .hidden = true;
  querySelector("#datasette_empty") .hidden = true;
  querySelector("#datasette_stopped").hidden = true;
  
  if (vic20.config.tapePlay) {
    querySelector("#datasette_play").hidden = false;
  } else if (vic20.tapeDrive.isTapeLoaded()) {
    querySelector("#datasette_stopped").hidden = false;
  } else {
    querySelector("#datasette_empty").hidden = false;
  }
}

bool isDartSupported() {
  try {
    // will throw exception if it doesn't exist
    //var dartExists = js.context.navigator.webkitStartDart;
    return true;
  }
  on NoSuchMethodError {
    return false;
  }
}

