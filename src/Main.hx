package;

import snow.api.buffers.Uint8Array;
import luxe.Input;
import moments.encoder.GifEncoder;
import moments.encoder.GifFrame;
import sys.io.File;

class Main extends luxe.Game {
	override function ready() {
        var encoder = new GifEncoder(-1, 10);
        encoder.SetDelay(1000);
        
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
        
        encoder.Start_File('out.gif');
        //var outStream = File.write('out_.gif');
        //encoder.Start_Output(outStream);
        encoder.AddFrame(frame1);
        encoder.AddFrame(frame2);
        encoder.AddFrame(frame3);
        encoder.AddFrame(frame4);
        encoder.Finish();
        //outStream.close();
	}

	override function onkeyup(e:KeyEvent) {
		if(e.keycode == Key.escape)
			Luxe.shutdown();
	}

	override function update(dt:Float) {
	}
}
