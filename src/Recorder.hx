package ;
import luxe.Vector;
import moments.encoder.GifEncoder;
import phoenix.RenderTexture;
import snow.api.buffers.Uint8Array;
import snow.modules.opengl.GL;
import Runner;

#if cpp
    import cpp.vm.Thread;
#elseif neko
    import neko.vm.Thread;
#end

class Recorder {
    public var state(default, null):RecorderState = Paused;
    public var lastSavedFrame(default, null):Int = -1;
    
    var encoder:GifEncoder;
    var quality:Int;
    var repeat:Int;
    var targetTex:RenderTexture;
    var frameWidth:Int;
    var frameHeight:Int;
    
    var savedFrames:Array<Uint8Array>;
    var frameDelays:Array<Float>;
    var minTimePerFrame:Float;
    var maxRecordingTime:Float;
    var maxFrames:Int;
    public var frameCount(default, null):Int = 0;
    
    var timeSinceLastSave:Float = 0;

    var saveThread:Thread;
    
    public function new(_frameWidth:Int, _frameHeight:Int, _maxFps:Int, _maxTime:Float, _quality:Int = 10, _repeat:Int = -1) {
        frameWidth = _frameWidth;
        frameHeight = _frameHeight;
        minTimePerFrame = 1 / _maxFps;
        maxRecordingTime = _maxTime;
        maxFrames = Math.round(_maxTime * _maxFps);
        quality = _quality;
        repeat = _repeat;
        
        targetTex = new RenderTexture( {
           id:'GifTargetTexture',
           width:frameWidth,
           height:frameHeight
        });
        
        savedFrames = [];
        frameDelays = [];
        Runner.init();
    }
    
    public function update() {
        Runner.run();
    }
    
    public function destroy() {
        if(state == Saving) abortSaving();
        targetTex.destroy(); //:todo: is all of the nulling necessary?
        savedFrames = null;
        frameDelays = null;
        saveThread = null;
    }

    public function pause() {
        if (state == Saving) {
            #if !no_gif_logging
                trace("Gif recorder / Recorder can't be paused while saving data. The recorder is paused automatically during saving"); 
            #end
            return;
        }
        
        state = Paused;
    }
    
    public function record() {
        if (state == Saving) {
            #if !no_gif_logging
                trace("Gif recorder / Can't start recording while the recorder is saving!");
            #end
            return;
        }
        
        state = Recording;
    }
    
    public function reset() {
        if (state == Saving) {
            #if !no_gif_logging
                trace("Gif recorder / Can't reset the recorder while saving!");
            #end
            return;
        }
        lastSavedFrame = -1;
        frameCount = 0;
        state = Paused;
        saveThread = null;
    }

    public function abortSaving(){
        if(state == Saving) saveThread.sendMessage(ThreadMessages.abort);
        state = Paused;
        reset();
    }
    
    public function save(path:String) {
        if (frameCount == 0) {
            #if !no_gif_logging
                trace('Gif recorder / Attempted save, but nothing has been recorded!');
            #end
            return;
        }
        
        state = Saving;
        #if !no_gif_logging
            trace('Gif recorder / Starting encoding');
        #end
        saveThread = Runner.thread(saveThreadFunc.bind(path));
    }
    
    function onEncodingFinished():Void {
        #if !no_gif_logging
            trace('Gif recorder / Encoding finished. Time taken was $savingTime seconds');
        #end
    }
    
    var savingTime:Float = 0;
    function saveThreadFunc(path:String):Void {
        var t = Luxe.time;
        var encoder = new GifEncoder(repeat, quality, true);
        encoder.SetDelay(Math.round(1000 * minTimePerFrame));
        encoder.Start_File(path);
        var gifFrame = {
            Width:frameWidth,
            Height:frameHeight,
            Data:new Uint8Array(frameWidth * frameHeight * 3)
        }
        
        RGBAtoRGB(savedFrames[0], gifFrame.Data);
        encoder.AddFrame(gifFrame);
        lastSavedFrame = 0;
        
        for (i in 1...frameCount) {
            if(Thread.readMessage(false) == ThreadMessages.abort){
                #if !no_gif_logging
                    Runner.call_primary(runTrace.bind('Gif recorder / Gif saving was stopped.')); //:todo: this may not be displayed if no recorder.update is run afterwards.
                #end
                break;
            }

            encoder.SetDelay(Math.round(1000 * frameDelays[i]));
            RGBAtoRGB(savedFrames[i], gifFrame.Data);
            encoder.AddFrame(gifFrame);
            lastSavedFrame = i;
        }
        
        encoder.Finish();
        state = Paused;
        reset();
        savingTime = Luxe.time - t;
        Runner.call_primary(onEncodingFinished);
    }
    //Copies RGBA pixel data from source to target as RGB pixels
    //source should be of length width * height * 4, and target of size width * height * 3
    function RGBAtoRGB(source:Uint8Array, target:Uint8Array):Void{
        for(i in 0...(frameWidth * frameHeight)){
           target.set(source.subarray(i * 4, i * 4 + 3), i * 3);
        }
    }
    
    public function onFrameRendered() {
        if (state != Recording) return;
        if (Luxe.time - timeSinceLastSave >= minTimePerFrame) {
            var oldViewport = Luxe.renderer.batcher.view.viewport.clone();
            Luxe.renderer.batcher.view.viewport.set(0, 0, frameWidth, frameHeight);
            Luxe.renderer.target = targetTex;
            Luxe.renderer.clear(Luxe.renderer.clear_color);
            Luxe.renderer.batcher.draw();
            Luxe.renderer.batcher.view.viewport.copy_from(oldViewport);

            if (savedFrames.length == frameCount) {
                savedFrames.push(new Uint8Array(frameWidth * frameHeight * 4));
                frameDelays.push(0);
            }

            GL.readPixels(0, 0, frameWidth, frameHeight, GL.RGBA, GL.UNSIGNED_BYTE, savedFrames[frameCount]);
            Luxe.renderer.target = null;

            frameDelays[frameCount] = Luxe.time - timeSinceLastSave;
            frameCount++;

            if (frameCount == maxFrames) {
                state = Paused;
                #if !no_gif_logging
                    trace('Gif recorder / Max frames reached!');
                #end
            }
            
            timeSinceLastSave = Luxe.time;
        }
    }

    public function runTrace(message:Dynamic):Void{
        trace(message);
    }
}

enum RecorderState {
    Recording;
    Paused;
    Saving;
}

@:enum
abstract ThreadMessages(Int){
    var abort = 1;
}