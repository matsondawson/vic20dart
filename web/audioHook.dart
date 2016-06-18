part of vic20dart;

class AudioHook {
  static ScriptProcessorNode _audioScriptProcessorNode;
  static Function onAudioProcess;
  static AudioContext _audioContext;
  
  static void localOnAudioProcess(AudioProcessingEvent event) {
    if (onAudioProcess!=null) onAudioProcess(event);
  }
  
  static void unhook() {
    onAudioProcess = null;
  }
  
  static double hook(void listener(AudioProcessingEvent event)) {
    onAudioProcess = listener;
    if (_audioScriptProcessorNode==null) {
      try {
        _audioContext = new AudioContext();
        _audioScriptProcessorNode = _audioContext.createScriptProcessor(2048, 0, 1)
            ..connectNode(_audioContext.destination, 0, 0)
            ..audioProcess.listen(localOnAudioProcess);
        
        print("Using webkit audio");
      }
      catch(e) {
        // Catch webkit audio not supported
        print(e);
        return null;
      }
    }
    
    return _audioContext.sampleRate;
  }
}