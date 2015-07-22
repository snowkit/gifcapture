package;

import phoenix.geometry.QuadGeometry;
import phoenix.RenderTexture;
import snow.api.buffers.Int32Array;
import snow.api.buffers.Uint8Array;
import luxe.Input;
import moments.encoder.GifEncoder;
import snow.modules.opengl.GL;
import sys.io.File;
import Recorder;
class Main extends luxe.Game {
    var boxGeom:QuadGeometry;
    var recorder:Recorder;

    override function ready() {
        boxGeom = Luxe.draw.box( {
           w:50,
           h:50,
           x:100,
           y:100
        });

        recorder = new Recorder(Std.int(Luxe.screen.w / 4), Std.int(Luxe.screen.h / 4), 30, 10, 100, 0);
    }

    override function onkeyup(e:KeyEvent) {
	    if (e.keycode == Key.escape) {
            recorder.destroy();
            recorder = null; // :todo: necessary?
            Luxe.shutdown();
        }
    }

    override public function onkeydown(event:KeyEvent) {
        switch(event.keycode) {
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
                var path = Luxe.snow.io.module.dialog_save('Save Gif');
                if(path != ''){
                    recorder.save(path);
                }
                else{
                    trace('Gif recorder / No file path specified, gif will not be saved!');
                }
        }
    }

    override public function onpostrender() {
        recorder.onFrameRendered();
    }

    override function update(dt:Float) {
        recorder.update();
        if (recorder.state == RecorderState.Saving) {
            Luxe.draw.box( {
               x:0,
               y:10,
               w:Luxe.screen.w * ((recorder.lastSavedFrame + 1) / recorder.frameCount),
               h:20,
               immediate:true
            });
        }

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
