package gifcapture;

import gif.GifEncoder;
import haxe.io.BytesOutput;
import haxe.io.UInt8Array;

#if cpp
    import cpp.vm.Thread;
    import cpp.vm.Deque;
#elseif neko
    import neko.vm.Thread;
    import neko.vm.Deque;
#end

class GifCapture {

    //public 

            /** Current state */
        public var state(default, null) : CaptureState = Paused;
            /** A callback that will be called with 0..1 for encoding progress.
                Encoding happens as soon as frames are added to the recorder.
                The callback is called on the thread the recorder is created on. */
        public var onprogress : Float->Void;

            /** A callback that will be called with the resulting encoded GIF bytes.
                The callback is called on the thread the recorder is created on. */
        public var oncomplete : haxe.io.Bytes->Void;

    //internal

            /** Maximum number of frames that can be recorded. 
                Intended to limit memory consumption and record fixed time lengths conveniently. */
        var max_frames : Int;
            /** The number of frames added to the recorder so far */
        var added : Int = 0;

            /** The frame rate of the gif in frames per second, i.e 24fps, 30fps, 50fps */
        var frame_rate : Int;
            /** Width of the gif */
        var frame_width : Int;
            /** Height of the gif */
        var frame_height : Int;

            /** The quality of the gif encoding. From 1 to 100, 1 being best quality but slowest processing, 100 being worst but fastest. */
        var quality : Int;
            /** How many times to repeat the gif. 
                use GifRepeat.None or GifRepeat.Infinite, 
                or a fixed amount. None = 0 is, Infinite = -1 */
        var repeat : Int;

            /** The thread in which the gif is being encoded. */
        var encoding_thread : Thread;
            /** The time it took for the last gif to encode. 
                Should only be written to by the encoding thread. */
        var encoding_time : Float = 0;
            /** The number of frames encoded. 
                Should only be written to by the encoding thread. */
        var encoding_count : Int = 0;

        /** Construct a new GifCapture object.
            The frame rate is used only if a given frame time is negative.
            max_time is used to limit memory consumption and make fixed length gifs, if <= 0 it is ignored.
            Quality is from 100 to 1. 1 is the best quality, but slower encoding. 100 is the worst quality but fastest encoding.
            Repeat is the number of times to loop, use GifRepeat or a fixed amount. */
    public function new(
            _frame_width:Int,
            _frame_height:Int,
            _frame_rate:Int,
            _max_time:Float,
            _quality:Int = 10,
            _repeat:Int = -1
    ) {

        frame_width = _frame_width;
        frame_height = _frame_height;
        frame_rate = _frame_rate;
        max_frames = Math.ceil(_max_time * _frame_rate);
        quality = _quality;
        repeat = _repeat;

        Runner.init();

        encoding_thread = Runner.thread(encoding_func);

        reset();

    }

    public function destroy() {

        encoding_thread.sendMessage(EncodingMessage.abort);

    } //destroy

        /** Call this in your update loop */
    public function update() {

        Runner.run();

    } //update

    public function pause() {

        if(state != Recording) return;

        state = Paused;

    } //pause

    public function record() {

        state = Recording;

    } //record

    public function reset() {

        added = 0;

        state = Paused;

        encoding_thread.sendMessage(EncodingMessage.reset);

    } //reset

        /** Signal the end of recording. When encoding is complete,
            the oncomplete callback will be triggered with the file data. */
    public function commit() {

        state = Committed;

        print('Finishing up...');

        encoding_thread.sendMessage(EncodingMessage.commit);

    } //commit


        /** The frame recording function. Call this to add frames to the gif. */
    public function add_frame(_rgb_pixels:UInt8Array, _frame_time:Float, _flippedY:Bool = false) {

        if(state != Recording) return;

        added++;

        var frame = {
            width:     frame_width,
            height:    frame_height,
            delay:    _frame_time,
            data:     _rgb_pixels,
            flippedY: _flippedY
        };

            //send the frame to the encoding thread
        encoding_thread.sendMessage(EncodingMessage.frame);
        encoding_thread.sendMessage(frame);

        frame = null;

        if(max_frames > 0 && added == max_frames) {
            print('Max frames reached');
            commit();
        }

    } //add_frame

    inline function print(v) {
        #if !no_gif_logging
            trace('GIF capture / $v');
        #end
    }

    //Background thread

        function encoding_func() {

            var encoder: GifEncoder = null;
            var output: BytesOutput = null;

            Sys.println("background thread ready");

            while(true) {

                var message = Thread.readMessage(false);

                switch(message) {

                    case EncodingMessage.abort: {

                        break;

                    } //abort

                    case EncodingMessage.reset: {

                        encoder = null;
                        output = null;
                        encoding_count = 0;
                        encoding_time = 0.0;

                        output = new BytesOutput();
                        encoder = new GifEncoder(
                            frame_width,
                            frame_height,
                            frame_rate,
                            repeat,
                            quality);

                        encoder.start(output);

                    } //reset

                    case EncodingMessage.commit: {

                        encoder.commit(output);

                        Runner.call_primary(encoding_complete.bind(output));

                    } //commit

                    case EncodingMessage.frame: {

                        var frame:GifFrame = Thread.readMessage(true);
                        var start = haxe.Timer.stamp();

                        encoder.add(output, frame);

                        encoding_time += haxe.Timer.stamp() - start;

                        encoding_count++;

                        Runner.call_primary(encoding_progress.bind(encoding_count));

                    } //frame

                    case _:

                } //switch(message)

                Sys.sleep(1/100); //Sleep the thread to allow other things to be scheduled and prevent this from using all of the cpu.

            } //while running

        } //encoding_func

    //callbacks

            /** Called at the end of the encoding process, 
                queued to the primary thread from the encoding thread. */
        function encoding_complete(output:BytesOutput) : Void {

            print('Encoding finished: took ~${encoding_time}s on ${encoding_count} frames');

            if(oncomplete != null) {

                var bytes = output.getBytes();

                oncomplete(bytes);

                bytes = null;

            } //oncomplete != null

            output = null;
            
            reset();

        } //encoding_complete

            /** Fires the onprogress callback with a value between 0..1,
                to indicate encoding progress. Called during the encoding process, 
                queued to the primary thread from the encoding thread. */
        function encoding_progress(index:Int) {

            if(onprogress != null) onprogress(index/added);

        } //encoding_progress

} //GifCapture

enum CaptureState {
    Paused;
    Recording;
    Committed;
}

@:enum
private abstract EncodingMessage(Int){
    var abort  = 1;
    var frame  = 2;
    var commit = 3;
    var reset  = 4;
}

// https://gist.github.com/underscorediscovery/e66e72ec702bdcedf5af45f8f4712109
private class Runner {

    public static var primary : Thread;

    static var queue : Deque<Void->Void>;

        /** Call this on your thread to make primary,
            the calling thread will be used for callbacks. */
    public static function init() {
        queue = new Deque<Void->Void>();
        primary = Thread.current();
    }

        /** Call this on the primary manually,
            Returns the number of callbacks called. */
    public static function run() : Int {

        var more = true;
        var count = 0;

        while(more) {
            var item = queue.pop(false);
            if(item != null) {
                count++; item(); item = null;
            } else {
                more = false; break;
            }
        }

        return count;

    } //process

        /** Call a function on the primary thread without waiting or blocking.
            If you want return values see call_primary_ret */
    public static function call_primary( _fn:Void->Void ) {

        queue.push(_fn);

    } //call_primary

        /** Call a function on the primary thread and wait for the return value.
            This will block the calling thread for a maximum of _timeout, default to 0.1s.
            To call without a return or blocking, use call_primary */
    public static function call_primary_ret<T>( _fn:Void->T, _timeout:Float=0.1 ) : Null<T> {

        var res:T = null;
        var start = haxe.Timer.stamp();
        var lock = new cpp.vm.Lock();

            //add to main to call this
        queue.push(function() {
            res = _fn();
            lock.release();
        });

            //wait for the lock release or timeout
        lock.wait(_timeout);

            //clean up
        lock = null;
            //return result
        return res;

    } //call_primary_ret

    public static function thread( fn:Void->Void ) : Thread {
        return Thread.create( fn );
    }

} //Runner