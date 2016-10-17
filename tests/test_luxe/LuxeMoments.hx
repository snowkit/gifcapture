import dialogs.Dialogs;
import luxe.Color;
import moments.Recorder;
import phoenix.Batcher;
import phoenix.RenderTexture;
import snow.modules.opengl.GL;

typedef GifQuality = gif.GifEncoder.GifQuality;
typedef GifRepeat = gif.GifEncoder.GifRepeat;
typedef RecorderState = moments.Recorder.RecorderState;

class LuxeMoments {

    //public 

        public var fps (default, set): Int = 30;
        public var state (get, never): RecorderState;
        public var force_default_fbo: Bool = true;

        public var color_busy: Color;
        public var color_paused: Color;
        public var color_recording: Color;

    //internal

        var recorder: Recorder;
        var dest: RenderTexture;
        var progress_view: Batcher;

        var mspf: Float = 1/30;
        var max_time: Float = 0.0;
        var progress: Float = 0.0;
    
    public function new(
        _width:Int, 
        _height:Int, 
        _fps:Int,
        _max_time:Float,
        _quality:Int,
        _repeat:Int
    ) {

        fps = _fps;
        max_time = _max_time;

        color_busy = new Color(0, 0.602, 1, 1);
        color_paused = new Color(1, 0.493, 0.061, 1);
        color_recording = new Color(0.968, 0.134, 0.019, 1);

        dest = new RenderTexture({
            id: 'moments_gif_dest',
            width: _width,
            height: _height,
        });

        recorder = new Recorder(
            _width, 
            _height, 
            _fps, 
            _max_time,
            _quality,
            _repeat);

        recorder.onprogress = onprogress;
        recorder.oncomplete = oncomplete;

        progress_view = new Batcher(Luxe.renderer, 'moments_gif_progress', 64);
        
        progress_view = Luxe.renderer.create_batcher({
            name:'moments_gif_progress',
            camera: new phoenix.Camera({ camera_name : 'moments_gif_progress_view' }),
            no_add: true,
            layer: 1000
        });

        Luxe.on(luxe.Ev.update, onupdate);
        Luxe.on(luxe.Ev.tickend, ontick);

    } //new

    //public 

        public function destroy() {

            Luxe.off(luxe.Ev.update, onupdate);
            Luxe.off(luxe.Ev.tickend, ontick);
                
            dest.destroy();
            progress_view.destroy();
            recorder.destroy();

            dest = null;
            recorder = null;
            progress_view = null;

        } //destroy

        public function reset() {

            progress = 0;
            recorder.reset();
            cpp.vm.Gc.enable(true);

        } //reset

        public function commit() {
            
            recorder.commit();
            cpp.vm.Gc.enable(true);

        } //commit

        public function record() {

            cpp.vm.Gc.enable(false);

            recorder.record();

        } //record

        public function pause() {

            cpp.vm.Gc.enable(true);

            recorder.pause();

        } //pause

    //internal

        function grab_frame() : haxe.io.Bytes {

            if(force_default_fbo) {
                GL.bindFramebuffer(GL.FRAMEBUFFER, Luxe.renderer.default_fbo);
            }

                //copy the current frame buffer to the texture framebuffer,
                //first we only bind the write portion to the dest
            GL.bindFramebuffer(opengl.GL.GL_DRAW_FRAMEBUFFER, dest.fbo);
            
                opengl.GL.glBlitFramebuffer(
                    0, 0, Luxe.screen.w, Luxe.screen.h, //src
                    0, 0, dest.width, dest.height, //dest
                    GL.COLOR_BUFFER_BIT,
                    GL.LINEAR
                );            

                //now we need to read from it
            GL.bindFramebuffer(opengl.GL.GL_READ_FRAMEBUFFER, dest.fbo);

                //get the pixels data back
            var frame_data = new snow.api.buffers.Uint8Array(dest.width * dest.height * 3);

            GL.readPixels(0, 0, dest.width, dest.height, GL.RGB, GL.UNSIGNED_BYTE, frame_data);

                //reset the frame buffer state
            GL.bindFramebuffer(GL.FRAMEBUFFER, Luxe.renderer.state.current_fbo);
            
            var frame_bytes = frame_data.toBytes();

            frame_data = null;

            return frame_bytes;

        }

    var last_tick = 0.0;
    var accum = 0.0;

    function onupdate(_) {

        recorder.update();

    } //onupdate

    function ontick(_) {

        if(recorder.state == Recording) {

            var frame_delta = Luxe.time - last_tick;
            last_tick = Luxe.time;

            accum += frame_delta;

            if(accum >= mspf) {

                var frame_bytes = grab_frame();
                var frame_in = haxe.io.UInt8Array.fromBytes(frame_bytes);
                
                recorder.add_frame(frame_in, mspf, true);

                frame_in = null;

                accum -= mspf;

            } //

        } //Recording

        if(progress != 0) {

            var color = switch(recorder.state) {
                case Recording: color_recording;
                case Paused:    color_paused;
                case _:         color_busy;
            }

            Luxe.draw.box({
                w: Luxe.screen.w * progress,                
                x: 0, y: 0, h: 3,
                batcher: progress_view,
                immediate: true,
                color: color
            });

            progress_view.draw();

        } //progress != 0

    } //tick_end


    //internal callbacks

        function oncomplete(_bytes:haxe.io.Bytes) {
            
            progress = 0;

            var path = Dialogs.save('Save GIF');

            if(path != '') {
                sys.io.File.saveBytes(path, _bytes);
            } else {
                trace('No path chosen, file not saved!');
            }

        } //oncomplete

        function onprogress(_progress:Float) {
            
            progress = _progress;

        } //onprogress

    //properties

        function get_state() {

            return recorder.state;

        } //get_state

        function set_fps(_v:Int) {
            
            mspf = 1 / _v;
            
            return fps = _v;

        } //set_fps

}