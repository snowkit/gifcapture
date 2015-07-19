package ;
import luxe.Vector;
import moments.encoder.GifEncoder;
import phoenix.RenderTexture;
import snow.api.buffers.Uint8Array;
import snow.modules.opengl.GL;
import Runner;

class Recorder {
    public var state(default, null):RecorderState = Paused;
    public var lastSavedFrame(default, null):Int = 0;
    
    var encoder:GifEncoder;
    var quality:Int;
    var repeat:Int;
    var targetTex:RenderTexture;
    var frameWidth:Int;
    var frameHeight:Int;
    
    var savedFrames:Array<Uint8Array>;
    var timePerFrame:Float;
    var maxRecordingTime:Float;
    var maxFrames:Int;
    public var frameCount(default, null):Int = 0;
    
    var timeSinceLastSave:Float = 0;
    
    public function new(_frameWidth:Int, _frameHeight:Int, _fps:Int, _maxTime:Float, _quality:Int = 10, _repeat:Int = -1) {
        frameWidth = _frameWidth;
        frameHeight = _frameHeight;
        timePerFrame = 1 / _fps;
        maxRecordingTime = _maxTime;
        maxFrames = Math.round(_maxTime * _fps);
        quality = _quality;
        repeat = _repeat;
        
        targetTex = new RenderTexture( {
           id:'GifTargetTexture',
           width:frameWidth,
           height:frameHeight
        });
        
        savedFrames = [];
        Runner.init();
    }
    
    public function pause() {
        if (state == Saving) {
            trace("Gif recorder / Recorder can't be paused while saving data. The recorder is paused automatically during saving");
            return;
        }
        
        state = Paused;
    }
    
    public function record() {
        if (state == Saving) {
            trace("Gif recorder / Can't start recording while the recorder is saving!");
            return;
        }
        
        state = Recording;
    }
    
    public function reset() {
        if (state == Saving) {
            trace("Gif recorder / Can't reset the recorder while saving!");
            return;
        }
        frameCount = 0;
        state = Paused;
    }
    
    public function save(path:String) {
        if (frameCount == 0) {
            trace('Gif recorder / Attempted save, but nothing has been recorded!');
            return;
        }
        
        state = Saving;
        
        Runner.thread(saveThreadFunc.bind(path));
    }
    
    function saveThreadFunc(path:String):Void {
        trace('Gif recorder / Started background thread for saving');
        var encoder = new GifEncoder(repeat, quality, true);
        encoder.SetDelay(Math.round(timePerFrame * 1000));
        encoder.Start_File(path);
        var gifFrame = {
            Width:frameWidth,
            Height:frameHeight,
            Data:savedFrames[0]
        }
        trace('Gif recorder / Starting gif encoding');
        
        for (i in 0...frameCount) {
            gifFrame.Data = savedFrames[i];
            encoder.AddFrame(gifFrame);
            lastSavedFrame = i;
        }
        
        encoder.Finish();
        state = Paused;
        lastSavedFrame = 0;
        reset();
        trace('Gif recorder / Encoding finished');
    }
    
    public function onFrameRendered() {
        if (state != Recording) return;
        if (Luxe.time - timeSinceLastSave >= timePerFrame) {
            var oldViewportSize = new Vector(Luxe.renderer.batcher.view.viewport.w, Luxe.renderer.batcher.view.viewport.h);
            Luxe.renderer.batcher.view.viewport.set(null, null, frameWidth, frameHeight);
            Luxe.renderer.target = targetTex;
            Luxe.renderer.clear(Luxe.renderer.clear_color);
            Luxe.renderer.batcher.draw();
            if (savedFrames.length == frameCount) savedFrames.push(new Uint8Array(frameWidth * frameHeight * 4));
            GL.readPixels(0, 0, frameWidth, frameHeight, GL.RGBA, GL.UNSIGNED_BYTE, savedFrames[frameCount]);
            Luxe.renderer.target = null;
            frameCount++;
            if (frameCount == maxFrames) {
                state = Paused;
                trace('Gif recorder / Max frames reached!');
            }
            Luxe.renderer.batcher.view.viewport.set(null, null, oldViewportSize.x, oldViewportSize.y);
            
            timeSinceLastSave = Luxe.time;
        }
        
    }
}

enum RecorderState {
    Recording;
    Paused;
    Saving;
}