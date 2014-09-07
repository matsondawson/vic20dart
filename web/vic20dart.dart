/**
 * Copyright matsondawson@gmail.com 2013
 */
library vic20dart;

import 'dart:js' as js;
//import 'package:js/js_wrapping.dart' as jsw;

import 'dart:html';
import 'dart:async';
import 'dart:web_audio';
import 'dart:typed_data';

part 'audioHook.dart';
part 'htmlScripts.dart';
part 'config.dart';
part 'common.dart';
part 'machineDefinition.dart';
part 'vic20.dart';
part 'cpu6502.dart';
part 'vic656x.dart';
part 'vic6560.dart';
part 'vic6561.dart';
part 'via6522.dart';
part 'via1.dart';
part 'via2.dart';
part 'ieee.dart';
part 'keyboard.dart';
part 'tapeDrive.dart';

void main() {
  //query("#noDartMessage").hidden = isDartSupported();
  
  Vic20 vic20 = new Vic20(new MachineDefinition.usa());
  //js.context.loadPrgJs        = new JsFunction().Callback.many((jsonData) => vic20.loadPrg(jsw.JsArrayToListAdapter.cast(jsonData)));
  js.context["toggleFullscreen"] = fullscreen;

  js.context["loadPrgJs"] = (bins) => vic20.loadPrg(bins);
  
  querySelectorAll(".machineDefinitionOption").forEach((cel) => cel.onClick.listen((event)
       => vic20.reinit(MachineDefinition.byKey(cel.attributes["data-machineDefinition"]), () => vic20.execute() )));
  
  querySelectorAll(".joykeysinput").forEach((cel)
       => cel.onClick.listen((event) => vic20.config.toggleJoykeys()));
  
  querySelectorAll(".speedOption" ).forEach((cel) => cel.onClick.listen((event)
       => vic20.config.speed = int.parse(cel.attributes["data-speed"])));
  
  //query("#datasettesmall").onClick.listen((event) => datasetteMouseClick(vic20));
  
  querySelector("#menuItem_softReset").onClick.listen((event) => vic20.softReset());
  querySelector("#menuItem_hardReset").onClick.listen((event) => vic20.reset());
  
  querySelectorAll("#programs > li").forEach((el) => el.onClick.listen((event) {
    fullscreen();
    var attrs = event.target.attributes;
    vic20.reinit(MachineDefinition.byKey(attrs["data-machineDefinition"]), () => loadProgramFromUrl(attrs["data-url"]));
  }));

  vic20.config.listen((Config config, String param) => configChange(vic20, config, param));
  vic20.execute();
}

void configChange(Vic20 vic20, Config config, String param) {
  querySelectorAll(".joykeysinput"            ).forEach((cel) => cel.checked = config.joykeys);
  querySelectorAll(".speedOption"             ).forEach((cel) => cel.checked = config.speed.toString()==cel.attributes["data-speed"]);
  querySelectorAll(".machineDefinitionOption" ).forEach((cel) => cel.checked = config.machineDefinitionKey==cel.attributes["data-machineDefinition"]);
}

bool loadProgramFromUrl(String url) {
  ScriptElement script = new Element.tag("script");
  script.src = "http://www.mdawson.net/vic20dart/prgtojsloader.php?cmd=loadPrgJs&prgurl=${url}";
  document.body.children.add(script);
  return false;
}




