
import phoenix.geometry.QuadGeometry;
import phoenix.RenderTexture;

import luxe.Input;
import gif.GifEncoder;
import snow.modules.opengl.GL;
import snow.api.buffers.*;

import moments.Recorder;


class Main extends luxe.Game {
    var boxGeom:QuadGeometry;
    var recorder:Recorder;

    override function config(config:luxe.GameConfig) {
        config.window.width = 480;
        config.window.height = 320;
        return config;
    }

    var progress:Float = 0.0;
    var progress_view:phoenix.Batcher;

    override function ready() {

        boxGeom = Luxe.draw.box( {
           w:50,
           h:50,
           x:100,
           y:100
        });        

        recorder = new Recorder(
            Std.int(Luxe.screen.w), 
            Std.int(Luxe.screen.h), 
            fps, 
            5, //max time
            GifQuality.Worst, 
            GifRepeat.Infinite);

        recorder.onprogress = function(_progress:Float) {
            progress = _progress;
        }

        progress_view = new phoenix.Batcher(Luxe.renderer, 'progress', 64);
        progress_view = Luxe.renderer.create_batcher({
            name:'progress_view',
            no_add: true,
            camera: new phoenix.Camera({ camera_name : 'progress_view_camera' }),
            layer: 1000
        });

        Luxe.on(luxe.Ev.tickend, tick_end);
    }

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
                    recorder.record();
                }
                else if (recorder.state == RecorderState.Recording) {
                    trace('pause recording');
                    recorder.pause();
                }
            case Key.key_r:
                trace('reset recorder');
                recorder.reset();
            case Key.key_3:
                var path = dialogs.Dialogs.save('Save GIF');
                if(path != '') {
                    recorder.save(path);
                } else{
                    trace('GIF recorder / No file path specified, GIF will not be saved!');
                }
        }
    }

    var last_tick = 0.0;
    var accum = 0.0;
    var fps = 50;
    var mspf = 1/50; //1/fps

    function tick_end(_) {

        var frame_delta = Luxe.time - last_tick;
        last_tick = Luxe.time;        

        accum += frame_delta;

        if(accum >= mspf) {

            var frame_data = new snow.api.buffers.Uint8Array(Luxe.screen.w * Luxe.screen.h * 3);
            GL.readPixels(0, 0, Luxe.screen.w, Luxe.screen.h, GL.RGB, GL.UNSIGNED_BYTE, frame_data);

            var frame_in = haxe.io.UInt8Array.fromBytes(frame_data.toBytes());
            recorder.add_frame(frame_in, mspf);

            frame_data = null;
            frame_in = null;

            accum -= mspf;

        } //

        if(progress != 0) {

            var color = new luxe.Color(0, 0.602, 1, 1);

            if(recorder.state != Paused) {
                color.set(0.968, 0.134, 0.019, 1);
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
