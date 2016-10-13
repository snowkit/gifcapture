
import phoenix.geometry.QuadGeometry;
import phoenix.RenderTexture;

import luxe.Input;
import gif.GifEncoder;
import snow.modules.opengl.GL;
import snow.api.buffers.*;

import moments.Recorder;

@:enum abstract GifQuality(Int) 
  from Int to Int {
    var Best = 1;
    var VeryHigh = 10;
    var QuiteHigh = 20;
    var High = 35;
    var Mid = 50;
    var Low = 65;
    var QuiteLow = 80;
    var VeryLow = 90;
    var Worst = 100;
}

@:enum abstract GifRepeat(Int) 
  from Int to Int {
    var NoLoop = -1;
    var Infinite = 0;
}

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

        recorder = new Recorder(Std.int(Luxe.screen.w), Std.int(Luxe.screen.h), 30, 10, GifQuality.Worst, GifRepeat.Infinite);

        Luxe.on(luxe.Ev.tickend, tick_end);
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
                var path = dialogs.Dialogs.save('Save GIF');
                if(path != ''){
                    recorder.save(path);
                }
                else{
                    trace('GIF recorder / No file path specified, GIF will not be saved!');
                }
        }
    }

    function tick_end(_) {
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
