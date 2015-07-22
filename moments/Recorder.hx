package moments;

import luxe.Vector;
import gif.GifEncoder;
import phoenix.RenderTexture;
import haxe.io.UInt8Array;
import snow.modules.opengl.GL;
import moments.Runner;

#if cpp
    import cpp.vm.Thread;
#elseif neko
    import neko.vm.Thread;
#end

class Recorder {
        /** Current recording state */
    public var state(default, null):RecorderState = Paused;
        /** Frame number of the frame most recently saved, updated by the background encoding thread. Ranges between 0 and frameCount - 1 */
    public var lastSavedFrame(default, null):Int = -1;
        /** Total number of frames recorded */
    public var frameCount(default, null):Int = 0;

        /** Minimum time the recorder waits to record another frame */
    var minTimePerFrame:Float;

        /** Maximum number of frames that can be recorded. Inteded to limit memory consumption. */
    var maxFrames:Int;

        /** Width of the gif */
    var frameWidth:Int;
        /** Height of the gif */
    var frameHeight:Int;

        /** The recorded frames which are then encoded into the gif. */
    var savedFrames:Array<snow.api.buffers.Uint8Array>;
        /** For each frame i in the savedFrames array, this records the actual difference in time between recording the frame and the frame before it, in seconds. */
    var frameDelays:Array<Float>;

        /** The actual gif encoder used in the background thread to save the gif. */
    var encoder:GifEncoder;
        /** The quality of the gif encoding. From 1 to 100, 1 being best quality but slowest processing, 100 being worst but fastest. */
    var quality:Int;
        /** How many times to repeat the gif. -1 means never (play only once), 0 means inifitely */
    var repeat:Int;
        /** Texture to which the scene is rendered to, from which the gif data is read */
    var targetTex:RenderTexture;

        /** Tracking variable for timing frame recording. */
    var timeSinceLastSave:Float = 0;
        /** The thread in which the gif is being encoded. */
    var saveThread:Thread;
        /** The time it took for the last gif to save. Should only be written to by the encoding thread. */
    var savingTime:Float = 0;

        /** Construct a new recorder object.
            _frameWidth and _frameHeigt: The dimensions of the resulting gif. Can be different to the screen size.
            _maxFPS: The maximum framerate of the gif, and the rate at which the recorder tries to record new frames for the gif.
            _maxTime: The maximum recording time for one gif, inteded to limit memory consumption.
            _quality: The encoding quality of the gif, from 1 to 100. 1 results in best quality, but slower processing. 100 gives worst quality but fastest processing.
            _repeat: The number of times the gif should repeat. -1 means never (play once), 0 means infinitely.
        */
    public function new(_frameWidth:Int, _frameHeight:Int, _maxFps:Int, _maxTime:Float, _quality:Int = 10, _repeat:Int = -1) {
        frameWidth = _frameWidth;
        frameHeight = _frameHeight;
        minTimePerFrame = 1 / _maxFps;
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

        /** Call this in your update loop to ensure the onEncodingFinished callback is being executed */
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

        /** Start the gif encoding and saving to a file specified by path. The file will be created if it does not exist, or overwritten otherwise. */
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

        /** Terminate the encoding thread and finish the gif at whatever point it was currently at. */
    public function abortSaving(){
        if(state == Saving) saveThread.sendMessage(ThreadMessages.abort);
        state = Paused;
        reset();
    }

        /** The frame recording function. Call this after each render loop of the game. */
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
                savedFrames.push(new snow.api.buffers.Uint8Array(frameWidth * frameHeight * 4));
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

    function saveThreadFunc(path:String):Void {
        var t = Luxe.time;
        var encoder = new GifEncoder(repeat, quality, true);
        encoder.setDelay(Math.round(1000 * minTimePerFrame));
        encoder.startFile(path);
        var gifFrame = {
            width:frameWidth,
            height:frameHeight,
            data: new UInt8Array(frameWidth * frameHeight * 3)
        }

        RGBAtoRGB(UInt8Array.fromBytes(savedFrames[0].toBytes()), gifFrame.data);
        encoder.addFrame(gifFrame);
        lastSavedFrame = 0;

        for (i in 1...frameCount) {
            if(Thread.readMessage(false) == ThreadMessages.abort){
                #if !no_gif_logging
                    Runner.call_primary(runTrace.bind('Gif recorder / Gif saving was stopped.')); //:todo: this may not be displayed if no recorder.update is run afterwards.
                #end
                break;
            }

            encoder.setDelay(Math.round(1000 * frameDelays[i]));
            RGBAtoRGB(UInt8Array.fromBytes(savedFrames[i].toBytes()), gifFrame.data);
            encoder.addFrame(gifFrame);
            lastSavedFrame = i;
        }

        encoder.finish();
        state = Paused;
        reset();
        savingTime = Luxe.time - t;
        Runner.call_primary(onEncodingFinished);
    }

        /** Copies RGBA pixel data from source to target as RGB pixels.
            Source should be of length width * height * 4, and target of size width * height * 3
        */
    function RGBAtoRGB(source:UInt8Array, target:UInt8Array):Void{
        for(i in 0...(frameWidth * frameHeight)) {
            target.view.buffer.blit(i * 3, source.view.buffer, i*4, 3);
        }
    }

        /** Called at the end of the encoding thread */
    function onEncodingFinished():Void {
        #if !no_gif_logging
            trace('Gif recorder / Encoding finished. Time taken was $savingTime seconds');
        #end
    }
        /** Used by the background encoding thread to emit traces on the primary thread */
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