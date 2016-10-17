
import phoenix.geometry.QuadGeometry;
import phoenix.RenderTexture;

import luxe.Input;
import gif.GifEncoder;
import snow.modules.opengl.GL;
import snow.api.buffers.*;

import moments.Recorder;
import snow.modules.opengl.GL;

class Main extends luxe.Game {
    var boxGeom:QuadGeometry;
    var recorder:Recorder;
    var dest: phoenix.RenderTexture;

    override function config(config:luxe.GameConfig) {
        config.window.width = 960;
        config.window.height = 640;
        return config;
    }

    var progress:Float = 0.0;
    var progress_view:phoenix.Batcher;


    static inline var fps = 50;
    static inline var mspf = 1/fps;         
    var gif_length = 5; //max length in seconds

    override function ready() {

        boxGeom = Luxe.draw.box( {
           w:50,
           h:50,
           x:100,
           y:100
        });

        dest = new phoenix.RenderTexture({
            id: 'gif_dest',
            width: Std.int(Luxe.screen.w/4),
            height: Std.int(Luxe.screen.h/4),
        });

        recorder = new Recorder(
            dest.width, dest.height, 
            fps, gif_length, 
            GifQuality.Worst,
            GifRepeat.Infinite);

        recorder.onprogress = function(_progress:Float) {
            progress = _progress;
        }

        recorder.oncomplete = function(_bytes:haxe.io.Bytes) {
            
            var path = dialogs.Dialogs.save('Save GIF');

            if(path != '') {
                sys.io.File.saveBytes(path, _bytes);
            } else {
                trace('No path chosen, file not saved!');
            }

        } //oncomplete

        progress_view = new phoenix.Batcher(Luxe.renderer, 'progress', 64);
        progress_view = Luxe.renderer.create_batcher({
            name:'progress_view',
            no_add: true,
            camera: new phoenix.Camera({ camera_name : 'progress_view_camera' }),
            layer: 1000
        });

        Luxe.on(luxe.Ev.tickend, tick_end);

    } //ready

    override function onkeyup(e:KeyEvent) {
	    if (e.keycode == Key.escape) {
            recorder.destroy();
            recorder = null;
            Luxe.shutdown();
        }
    }

    override public function onkeydown(event:KeyEvent) {
        switch(event.keycode) {
            case Key.key_v:
                sdl.SDL.GL_SetSwapInterval(false);

            case Key.space:
                if (recorder.state == RecorderState.Paused) {
                    trace('turn on recording');
                    cpp.vm.Gc.enable(false);
                    recorder.record();
                } else if (recorder.state == RecorderState.Recording) {
                    trace('pause recording');
                    recorder.pause();
                    cpp.vm.Gc.enable(true);
                }

            case Key.key_r:
                trace('reset recorder');
                recorder.reset();

            case Key.key_3:
                trace('commit recording');
                recorder.commit();
        }
    }


    var last_tick = 0.0;
    var accum = 0.0;
    function tick_end(_) {

        if(recorder.state == Recording) {

            var frame_delta = Luxe.time - last_tick;
            last_tick = Luxe.time;

            accum += frame_delta;

            if(accum >= mspf) {

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
                var frame_in = haxe.io.UInt8Array.fromBytes(frame_bytes);
                
                recorder.add_frame(frame_in, mspf);

                frame_data = null;
                frame_in = null;

                accum -= mspf;

            } //

        } //Recording

        if(progress != 0) {

            var color = new luxe.Color(0, 0.602, 1, 1);

            switch(recorder.state) {
                case Recording:
                    color.set(0.968, 0.134, 0.019, 1);
                case Paused:
                    color.set(0.75, 0.75, 0.8, 1);
                case Committed:
                    color.set(1, 0.493, 0.061, 1);
            }

            Luxe.draw.box({
                batcher: progress_view,
                x: 0, y: 0, h: 3,
                w: Luxe.screen.w * progress,
                color: color,
                immediate: true
            });

            progress_view.draw();

        } //Saving

    } //tick_end

    override function onrender() {

        Luxe.draw.text({
            immediate: true,
            pos: new luxe.Vector(10, 10),
            point_size: 14,
            text: '${Luxe.time}'
        });

    }

    override function update(dt:Float) {

        recorder.update();

        if (Luxe.input.keydown(Key.key_a)) {
            boxGeom.transform.pos.x -= 200 * dt;
        }
        else if (Luxe.input.keydown(Key.key_d)) {
           boxGeom.transform.pos.x += 200 * dt;
        }

        if (Luxe.input.keydown(Key.key_w)) {
           boxGeom.transform.pos.y -= 200 * dt;
        }
        else if (Luxe.input.keydown(Key.key_s)) {
           boxGeom.transform.pos.y += 200 * dt;
        }
    }
}
