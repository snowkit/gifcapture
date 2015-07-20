package;

import phoenix.geometry.QuadGeometry;
import phoenix.RenderTexture;
import snow.api.buffers.Int32Array;
import snow.api.buffers.Uint8Array;
import luxe.Input;
import moments.encoder.GifEncoder;
import moments.encoder.GifFrame;
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
        
        recorder = new Recorder(Std.int(Luxe.screen.w / 2), Std.int(Luxe.screen.h / 2), 60, 10, 100, 0);
    }
    
	override function onkeyup(e:KeyEvent) {
		if (e.keycode == Key.escape) {
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
                recorder.reset();
            case Key.key_1:
                recorder.save('recording.gif');
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
               w:Luxe.screen.w * (recorder.lastSavedFrame / recorder.frameCount),
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
