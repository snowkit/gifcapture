package;

import phoenix.geometry.QuadGeometry;
import snow.api.buffers.Uint8Array;
import luxe.Input;
import moments.encoder.GifEncoder;
import moments.encoder.GifFrame;
import snow.modules.opengl.GL;
import sys.io.File;

class Main extends luxe.Game {
    var boxGeom:QuadGeometry;
    var encoder:GifEncoder;
    var frame:GifFrame;
    var timestamp:Float;
	override function ready() {
        
        boxGeom = Luxe.draw.box( {
           w:50,
           h:50,
           x:100,
           y:100
        });
        
        encoder = new GifEncoder(-1, 100, true);
        encoder.Start_File('screenTest.gif');
        
        frame = {
            Width:Luxe.screen.w,
            Height:Luxe.screen.h,
            Data:new Uint8Array(Luxe.screen.w * Luxe.screen.h * 3)
        }
        timestamp = Luxe.time;
        
        /*
        encoder.Start_File('out.gif');
        var frame1:GifFrame = {
            Width:2,
            Height:2,
            Data:new Uint8Array([255,255,255, 0,0,0, 0,0,0, 0,0,0])
        }
        
        var frame2:GifFrame = {
            Width:2,
            Height:2,
            Data:new Uint8Array([0,0,0, 255,255,255, 0,0,0, 0,0,0])
        }
        
        var frame3:GifFrame = {
            Width:2,
            Height:2,
            Data:new Uint8Array([0,0,0, 0,0,0, 255,255,255, 0,0,0])
        }
        
        var frame4:GifFrame = {
            Width:2,
            Height:2,
            Data:new Uint8Array([0,0,0, 0,0,0, 0,0,0, 255,255,255])
        }
        encoder.AddFrame(frame1);
        encoder.AddFrame(frame2);
        encoder.AddFrame(frame3);
        encoder.AddFrame(frame4);
        encoder.Finish();
        */
	}

	override function onkeyup(e:KeyEvent) {
		if (e.keycode == Key.escape) {
            encoder.Finish();
			Luxe.shutdown();
        }
	}
    
    override public function onpostrender() {
        GL.readPixels(0, 0, Luxe.screen.w, Luxe.screen.h, GL.RGB, GL.UNSIGNED_BYTE, frame.Data);
        timestamp = Luxe.time;
        encoder.AddFrame(frame);
        trace(Luxe.time - timestamp);
        timestamp = Luxe.time;
        encoder.SetDelay(Std.int(Luxe.dt * 1000));
        //encoder.Finish();
        //Luxe.shutdown();
    }

	override function update(dt:Float) {
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
