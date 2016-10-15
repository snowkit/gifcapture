package moments;

import gif.GifEncoder;
import haxe.io.BytesOutput;
import phoenix.RenderTexture;
import haxe.io.UInt8Array;
import moments.Runner;

#if cpp
    import cpp.vm.Thread;
#end

class Recorder {
        /** Current recording state */
    public var state(default, null):RecorderState = Paused;
        /** Frame number of the frame most recently saved, updated by the background encoding thread. Ranges between 0 and frameCount - 1 */
    public var lastSavedFrame(default, null):Int = -1;
        /** Total number of frames recorded */
    public var frameCount(default, null):Int = 0;

        /** Maximum number of frames that can be recorded. Inteded to limit memory consumption. */
    var maxFrames:Int;

        /** framerate */
    var framerate:Int;
        /** Width of the gif */
    var frameWidth:Int;
        /** Height of the gif */
    var frameHeight:Int;

    var flipped:Bool = true;

    var filePath:String = 'moment.gif';

        /** The recorded frames which are then encoded into the gif. */
    var savedFrames:Array<GifFrame>;

        /** The actual gif encoder used in the background thread to save the gif. */
    var encoder:GifEncoder;
        /** The quality of the gif encoding. From 1 to 100, 1 being best quality but slowest processing, 100 being worst but fastest. */
    var quality:Int;
        /** How many times to repeat the gif. -1 means never (play only once), 0 means inifitely */
    var repeat:Int;

        /** Tracking variable for timing frame recording. */
    var timeSinceLastSave:Float = 0;
        /** The thread in which the gif is being encoded. */
    var saveThread:Thread;
    var encoding_thread:Thread;
        /** The time it took for the last gif to save. Should only be written to by the encoding thread. */
    var savingTime:Float = 0;

    public var onprogress:Float->Void;

        /** Construct a new recorder object.
            _frameWidth and _frameHeigt: The dimensions of the resulting gif. Can be different to the screen size.
            _framerate: The desired framerate of the gif, only used if a given frame time is negative
            _maxTime: The maximum recording time for one gif, inteded to limit memory consumption.
            _quality: The encoding quality of the gif, from 1 to 100. 1 results in best quality, but slower processing. 100 gives worst quality but fastest processing.
            _repeat: The number of times the gif should repeat. -1 means never (play once), 0 means infinitely.
        */
    public function new(
            _frameWidth:Int, 
            _frameHeight:Int, 
            _framerate:Int, 
            _maxTime:Float, 
            _quality:Int = 10, 
            _repeat:Int = -1
    ) {

        frameWidth = _frameWidth;
        frameHeight = _frameHeight;
        framerate = _framerate;
        maxFrames = Math.ceil(_maxTime * _framerate);
        quality = _quality;
        repeat = _repeat;

        savedFrames = [];
        Runner.init();
        encoding_thread = Runner.thread(encoding_func);

    }

        /** Call this in your update loop to ensure the onEncodingFinished callback is being executed */
    public function update() {
        Runner.run();
    }

    public function destroy() {
        
        encoding_thread.sendMessage(ThreadMessages.abort);

        if(state == Saving) {
            abortSaving();
        }

        savedFrames = null;
        saveThread = null;


    }

    public function pause() {
        
        if (state == Saving) {
            print("Recorder can't be paused while saving data. The recorder is paused automatically during saving");
            return;
        }

        state = Paused;

    } //pause

    public function record() {
        
        if (state == Saving) {
            print("Can't start recording while the recorder is saving!");
            return;
        }

        state = Recording;

    } //record

    public function reset() {

        if (state == Saving) {
            print("Can't reset the recorder while saving!");
            return;
        }

        lastSavedFrame = -1;
        frameCount = 0;
        state = Paused;
        saveThread = null;
    
    } //reset

        /** Start the gif encoding and saving to a file specified by path. The file will be created if it does not exist, or overwritten otherwise. */
    public function save(path:String) {
        
        if(added == 0) {
            print('Attempted save, but nothing has been recorded!');
            return;
        }

        print('Finishing up...');

        filePath = path;
        encoding_thread.sendMessage(ThreadMessages.commit);

    } //save

        /** Terminate the encoding thread and finish the gif at whatever point it was currently at. */
    public function abortSaving(){

        if(state == Saving) saveThread.sendMessage(ThreadMessages.abort);

        state = Paused;

        reset();

    } //abortSaving

    var added = 0;

        /** The frame recording function. Call this to add frames to the gif. */
    public function add_frame(rgb_pixels:UInt8Array, frame_time:Float) {

        if(state != Recording) return;

        added++;

        var frame = {
            width: frameWidth,
            height: frameHeight,
            delay: frame_time,
            data: rgb_pixels
        };

            //send the frame to the encoding thread
        encoding_thread.sendMessage(ThreadMessages.frame);
        encoding_thread.sendMessage(frame);

        frame = null;

        if(added == maxFrames) {
            state = Paused;
        }

    } //add_frame

    //     /** The frame recording function. Call this to add frames to the gif. */
    // public function add_frame(rgb_pixels:UInt8Array, frame_time:Float) {

    //     if(state != Recording) return;

    //         //We only push frames if we need them, because
    //         //if we call repeatedly we don't have to reallocate the data
    //     if(savedFrames.length == frameCount) {                

    //         savedFrames.push({
    //             width: frameWidth, height: frameHeight, delay: 0, data: null
    //         });

    //     } // if last frame

    //     var frame = savedFrames[frameCount];

    //             //we make a copy of the data because 
    //             //we're encoding in a background thread and need it to stick around
    //         frame.data = new UInt8Array(frameWidth * frameHeight * 3);
    //         frame.data.view.buffer.blit(0, rgb_pixels.view.buffer, 0, frame.data.length);
    //         frame.delay = frame_time;

    //     timeSinceLastSave = haxe.Timer.stamp();
    //     frameCount++;

    //     if(frameCount == maxFrames) {
    //         state = Paused;
    //         print('Max frames reached!');
    //     }

    // } //add_frame

    inline function print(v) {
        #if !no_gif_logging 
            trace('Gif recorder / $v'); 
        #end
    }

    function encoding_func() {

        var running = true;
        var encoder = new GifEncoder(
            frameWidth,
            frameHeight,
            framerate,
            repeat, 
            quality, 
            flipped);

        var output = new BytesOutput();
        var count = 0;
        
        encoder.start(output);

        Sys.println("background thread ready");

        while(running) {
            
            var message = Thread.readMessage(false);

            switch(message) {
                
                case ThreadMessages.abort: {

                    running = false;

                } //abort
                
                case ThreadMessages.commit: {
    
                    encoder.commit(output);

                    Runner.call_primary(encoding_complete.bind(output));
                
                } //commit

                case ThreadMessages.frame: {

                    var frame:GifFrame = Thread.readMessage(true);

                    encoder.add(output, frame);

                    count++;

                    Runner.call_primary(encoding_progress.bind(count));

                } //frame

                case _:

            } //switch(message)

            Sys.sleep(0.0);

        } //while running

    } //encoding_func

    // function saveThreadFunc(path:String):Void {

    //     var t = haxe.Timer.stamp();
    //     var encoder = new GifEncoder(framerate, repeat, quality, true);
    //     encoder.startFile(path);

    //     lastSavedFrame = 0;
    //     encoder.addFrame(savedFrames[0]);

    //     for(i in 1...frameCount) {

    //         if(Thread.readMessage(false) == ThreadMessages.abort) {
    //                 //:todo: this may not be displayed if no recorder.update is run afterwards.
    //             #if !no_gif_logging Runner.call_primary(runTrace.bind('Gif recorder / Gif saving was stopped.')); #end
    //             break;
    //         }

    //         encoder.addFrame(savedFrames[i]);

    //         lastSavedFrame = i;

    //     } //each frame

    //     encoder.finish();
    //     state = Paused;
    //     reset();
    //     savingTime = haxe.Timer.stamp() - t;
    //     Runner.call_primary(onEncodingFinished);
    
    // } //saveThreadFunc

        /** Called at the end of the encoding thread */
    function encoding_complete(output:BytesOutput) : Void {

        var bytes = output.getBytes();

        sys.io.File.saveBytes(filePath, bytes);

        output = null;
        bytes = null;

        print('Encoding finished. Time taken was $savingTime seconds');

        reset();

    } //encoding_complete

        //
    function encoding_progress(index:Int) {

        Sys.println('encoding progress $index / $added');
        if(onprogress != null) {
            onprogress(index/added);
        }

    } //encoding_progress

        /** Used by the background encoding thread to emit traces on the primary thread */
    function runTrace(message:Dynamic):Void{
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
    var frame = 2;
    var commit = 3;
}