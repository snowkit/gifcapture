package gif;

/*
 * No copyright asserted on the source code of this class. May be used
 * for any purpose.
 *
 * Original code by Kevin Weiner, FM Software.
 * Adapted by Thomas Hourdel (https://github.com/Chman/Moments)
 * Ported to Haxe by Tilman Schmidt and Sven Bergström
 */

import sys.io.File;
import sys.io.FileOutput;
import haxe.io.UInt8Array;

import haxe.io.BytesOutput;


@:enum abstract GifRepeat(Int)
  from Int to Int {
    var NoLoop = -1;
    var Infinite = 0;
}

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

class GifEncoder {

    var width:Int;
    var height:Int;
    var framerate:Int = 24;                 // used if frame.delay < 0
    var repeat:Int = -1;                    // -1: no repeat, 0: infinite, >0: repeat count
    var hasStarted:Bool = false;            // Ready to output frames
    var fileStream:FileOutput;

    var currentFrame:GifFrame;
    var pixels:UInt8Array;
    var flippedY:Bool = false;
    var indexedPixels:UInt8Array;           // Converted frame indexed to palette
    var colorDepth:Int = 8;                 // Number of bit planes
    var colorTab:UInt8Array;                // RGB palette
    var usedEntry:Array<Bool>;              // Active palette entries
    var paletteSize:Int = 7;                // Color table size (bits-1)
    var disposalCode:Int = -1;              // Disposal code (-1 = use default)
    var shouldCloseStream:Bool = false;     // Close stream when finished
    var isFirstFrame:Bool = true;
    var isSizeSet:Bool = false;             // If false, get size from first frame
    var sampleInterval:Int = 10;            // Default sample interval for quantizer

    var nq:NeuQuant;
    var lzwEncoder:LzwEncoder;

// Public API

    /** Construct a gif encoder with options:

        frame width/height:
            Default is 0, required

        framerate:
            This is used if an added frame has a delay that is negative.

        repeat:
            Default is -1 (no repeat); 0 means play indefinitely.
            Use GifRepeat for clarity

        quality:
            Sets quality of color quantization (conversion of images to
            the maximum 256 colors allowed by the GIF specification). Lower values (minimum = 1)
            produce better colors, but slow processing significantly. Higher values will speed
            up the quantization pass at the cost of lower image quality (maximum = 100).

        flippedY:
            If the frame is expected to be flipped during encoding for alternative coordinate systems */
    public function new(
        _frame_width:Int,
        _frame_height:Int,
        _framerate:Int,
        _repeat:GifRepeat = GifRepeat.Infinite,
        _quality:Int = 10,
        _flippedY:Bool = false
    ) {

        width = _frame_width;
        height = _frame_height;
        framerate = _framerate;
        repeat = _repeat;
        flippedY = _flippedY;

        sampleInterval = Std.int(clamp(_quality, 1, 100));
        usedEntry = [for (i in 0...256) false];

        pixels = new UInt8Array(width * height * 3);
        indexedPixels = new UInt8Array(width * height);

        nq = new NeuQuant();
        lzwEncoder = new LzwEncoder();

    } //new

    // //
    //     /** Adds next GIF frame. The frame is not written immediately, but is actually deferred
    //         until the next frame is received so that timing data can be inserted. Invoking
    //         Finish() flushes all frames. */
    //     var last_delay:Float = 0.0;
    //     public function addFrame(frame:GifFrame):Void
    //     {
    //         if (!hasStarted)
    //         {
    //             throw "Call Start() before adding frames to the gif.";
    //         }

    //         // Use first frame's size
    //         if (!isSizeSet)
    //         {
    //             setSize(frame.width, frame.height);
    //         }

    //         currentFrame = frame;
    //         getImagepixels();
    //         analyzepixels();

    //         if (isFirstFrame)
    //         {
    //             writeLSD();
    //             writePalette();

    //             if (repeat >= 0)
    //             {
    //                 writeNetscapeExt();
    //             }
    //         }

    //         writeGraphicCtrlExt(last_delay);

    //         if(frame.delay < 0) {
    //             last_delay = 1.0/framerate;
    //         } else {
    //             last_delay = frame.delay;
    //         }

    //         writeImageDesc();

    //         if (!isFirstFrame)
    //         {
    //             writePalette();
    //         }

    //         writePixels();
    //         isFirstFrame = false;
    //     }

    //     /** Initiates GIF file creation on the given stream.
    //         The stream is not closed automatically.
    //         The FileOutput on which GIF images are written,
    //         should to binary and little endian. */
    //     public function startOutput(out:FileOutput):Void
    //     {
    //         if (out == null) {
    //             throw "File output is null.";
    //         }

    //         shouldCloseStream = false;
    //         fileStream = out;

    //         try {
    //             fileStream.writeString("GIF89a"); // header
    //         }
    //         catch (e:Dynamic) {
    //             throw e;
    //         }

    //         hasStarted = true;
    //     }

    //     /** Initiates writing of a GIF file with the specified name.
    //         The stream will be handled for you. */
    //     public function startFile(path:String):Void
    //     {
    //         try {
    //             fileStream = File.write(path);
    //             startOutput(fileStream);
    //             shouldCloseStream = true;
    //         }
    //         catch (e:Dynamic) {
    //             throw e;
    //         }
    //     }


//
    
    //writers

            /** Writes Logical Screen Descriptor. */
        function write_LSD(output:BytesOutput) {
            //
            
                // Logical screen size
            output.writeInt16(width);
            output.writeInt16(height);

                // Packed fields
            output.writeByte(0x80 |         // 1   : global color table flag = 1 (gct used)
                             0x70 |         // 2-4 : color resolution = 7
                             0x00 |         // 5   : gct sort flag = 0
                             paletteSize);  // 6-8 : gct size

            output.writeByte(0);            // Background color index
            output.writeByte(0);            // Pixel aspect ratio - assume 1:1

        } //write_LSD

            /** Writes Netscape application extension to define repeat count. */
        function write_NetscapeExt(output:BytesOutput):Void {

            output.writeByte(0x21);    // Extension introducer
            output.writeByte(0xff);    // App extension label
            output.writeByte(11);      // Block size
            output.writeString("NETSCAPE" + "2.0"); // App id + auth code
            output.writeByte(3);       // Sub-block size
            output.writeByte(1);       // Loop sub-block id
            output.writeInt16(repeat); // Loop count (extra iterations, 0=repeat forever)
            output.writeByte(0);       // Block terminator

        } //write_NetscapeExt

            /** Write color table. */
        function write_palette(output:BytesOutput):Void {
            
            output.write(colorTab.view.buffer);

            var n:Int = (3 * 256) - colorTab.length;

            for (i in 0...n) {
                output.writeByte(0);
            }

        } //write_palette

            /** Encodes and writes pixel data. */
        function write_pixels(output:BytesOutput):Void {
        
            lzwEncoder.reset(indexedPixels, colorDepth);
            lzwEncoder.encode(output);
        
        } //write_pixels

            /** Writes Image Descriptor. */
        function write_image_desc(output:BytesOutput, first:Bool):Void {

            output.writeByte(0x2c);         // Image separator
            output.writeInt16(0);           // Image position x = 0
            output.writeInt16(0);           // Image position y = 0
            output.writeInt16(width);       // Image width
            output.writeInt16(height);      // Image height

                //Write LCT, or GCT

            if(first) {

                output.writeByte(0);                // No LCT  - GCT is used for first (or only) frame

            } else {
                    
                output.writeByte(0x80 |             // 1 local color table  1=yes
                                    0 |             // 2 interlace - 0=no
                                    0 |             // 3 sorted - 0=no
                                    0 |             // 4-5 reserved
                                    paletteSize);   // 6-8 size of color table
            
            } //else

        } //write_image_desc

            /** Writes Graphic Control Extension. Delay is in seconds, floored and converted to 1/100 of a second */
        function write_GraphicControlExt(output:BytesOutput, delay:Float):Void {

            output.writeByte(0x21);         // Extension introducer
            output.writeByte(0xf9);         // GCE label
            output.writeByte(4);            // data block size

            // Packed fields
            output.writeByte(0 |            // 1:3 reserved
                             0 |            // 4:6 disposal
                             0 |            // 7   user input - 0 = none
                             0 );           // 8   transparency flag

                //convert to 1/100 sec
            var delay_val = Math.floor(delay * 100);

            output.writeInt16(delay_val);   // Delay x 1/100 sec
            output.writeByte(0);            // Transparent color index
            output.writeByte(0);            // Block terminator

        } //write_GraphicControlExt


    var started = false;
    var first_frame = true;

    public function start(output:BytesOutput) {

        if(output == null) throw "gif: output must be not null.";

        output.writeString("GIF89a");

        write_LSD(output);

        started = true;

    } //start

    public function commit(output:BytesOutput) {

        if(output == null) throw "gif: output must be not null.";
        if(!started) throw "gif: commit() called without start() being called first.";

        output.writeByte(0x3b); // Gif trailer
        output.flush();
        output.close();

        started = false;
        first_frame = true;
        last_delay = 0.0;

    } //commit

    function get_pixels(frame:GifFrame):UInt8Array {
        //

            //if not flipped we can use the data as is
        if (!flippedY) return frame.data;

            //otherwise flip it, and return the cached array
        var stride = width * 3;
        for(y in 0...height) {
            var begin = (height - 1 - y) * stride;
            pixels.view.buffer.blit(y * stride, frame.data.view.buffer, begin, stride);
        }

        return pixels;

    } //get_pixels

    function analyze(pixels:UInt8Array) {

        // Create reduced palette
        nq.reset(pixels, pixels.length, sampleInterval);
        colorTab = nq.process();

            // Map image pixels to new palette
        var k:Int = 0;
        for (i in 0...(width * height)) {
            var r = pixels[k++] & 0xff;
            var g = pixels[k++] & 0xff;
            var b = pixels[k++] & 0xff;
            var index = nq.map(r, g,b);
            usedEntry[index] = true;
            indexedPixels[i] = index;
        }

    } //analyze

    var last_delay:Float = 0.0;

    public function add(output:BytesOutput, frame:GifFrame):Void {

        if(!started) throw "gif: call start() before adding frames.";

        var pixels = get_pixels(frame);
        analyze(pixels);

        if(first_frame) {
            
            write_palette(output);
            
            if(repeat >= 0) {
                write_NetscapeExt(output);
            }

            first_frame = false;

        } //first_frame

        write_GraphicControlExt(output, last_delay);

        if(frame.delay < 0) {
            last_delay = 1.0/framerate;
        } else {
            last_delay = frame.delay;
        }

        write_image_desc(output, first_frame);

        if(!first_frame) {
            write_palette(output);
        }

        write_pixels(output);

    } //add

///

//     /** Flushes any pending data and closes output file.
//         If writing to a FileOutput, the stream is not closed. */
//     public function finish():Void
//     {
//         if (!hasStarted)
//         {
//             throw "Can't finish a non-started gif.";
//         }

//         hasStarted = false;

//         try
//         {
//             fileStream.writeByte(0x3b); // Gif trailer
//             fileStream.flush();

//             if (shouldCloseStream) {
//                 fileStream.close();
//             }
//         }
//         catch (e:Dynamic)
//         {
//             throw e;
//         }

//         // Reset for subsequent use
//         fileStream = null;
//         currentFrame = null;
//         indexedPixels = null;
//         colorTab = null;
//         shouldCloseStream = false;
//         isFirstFrame = true;
//     }

// //Internal

//     /** Get the current frame pixel data, will be flipped if the flag is enabled */
//     function getImagepixels():Void {

//         if (!flippedY) {
//             pixels = currentFrame.data;
//         } else {
//             var stride = currentFrame.width * 3;
//             for(y in 0...currentFrame.height) {
//                 var begin = (currentFrame.height - 1 - y) * stride;
//                 pixels.view.buffer.blit(y * stride, currentFrame.data.view.buffer, begin, stride);
//             }
//         }

//     } //

//     /** Analyzes image colors and creates color map. */
//     function analyzepixels():Void
//     {
//         nq.reset(pixels, pixels.length, sampleInterval);
//         colorTab = nq.process(); // Create reduced palette

//         // Map image pixels to new palette
//         var k:Int = 0;
//         for (i in 0...(currentFrame.width * currentFrame.height))
//         {
//             var index = nq.map(pixels[k++] & 0xff, pixels[k++] & 0xff, pixels[k++] & 0xff);
//             usedEntry[index] = true;
//             indexedPixels[i] = index;
//         }

//         colorDepth = 8;
//         paletteSize = 7;

//     }

// //Stream Encoding

//     /** Writes Graphic Control Extension. Delay is in seconds, floored and converted to 1/100 of a second */
//     function writeGraphicCtrlExt(delay:Float):Void
//     {
//         fileStream.writeByte(0x21);         // Extension introducer
//         fileStream.writeByte(0xf9);         // GCE label
//         fileStream.writeByte(4);            // data block size

//         // Packed fields
//         fileStream.writeByte(0 |            // 1:3 reserved
//                              0 |            // 4:6 disposal
//                              0 |            // 7   user input - 0 = none
//                              0 );           // 8   transparency flag


//         fileStream.writeInt16(Math.round(delay * 100)); // Delay x 1/100 sec
//         fileStream.writeByte(0);                        // Transparent color index
//         fileStream.writeByte(0);                        // Block terminator
//     }

//     /** Writes Image Descriptor. */
//     function writeImageDesc():Void
//     {
//         fileStream.writeByte(0x2c);         // Image separator
//         fileStream.writeInt16(0);           // Image position x,y = 0,0
//         fileStream.writeInt16(0);
//         fileStream.writeInt16(width);       // image size
//         fileStream.writeInt16(height);

//         // Packed fields
//         if (isFirstFrame)
//         {
//             fileStream.writeByte(0);                // No LCT  - GCT is used for first (or only) frame
//         }
//         else
//         {
//             // Specify normal LCT
//             fileStream.writeByte(0x80 |             // 1 local color table  1=yes
//                                     0 |             // 2 interlace - 0=no
//                                     0 |             // 3 sorted - 0=no
//                                     0 |             // 4-5 reserved
//                                     paletteSize);   // 6-8 size of color table
//         }
//     }

//     /** Writes Logical Screen Descriptor. */
//     function writeLSD():Void
//     {
//         // Logical screen size
//         fileStream.writeInt16(width);
//         fileStream.writeInt16(height);

//         // Packed fields
//         fileStream.writeByte(0x80 |         // 1   : global color table flag = 1 (gct used)
//                              0x70 |         // 2-4 : color resolution = 7
//                              0x00 |         // 5   : gct sort flag = 0
//                              paletteSize);  // 6-8 : gct size

//         fileStream.writeByte(0);            // Background color index
//         fileStream.writeByte(0);            // Pixel aspect ratio - assume 1:1
//     }

//         /** Writes Netscape application extension to define repeat count. */
//     function writeNetscapeExt():Void
//     {
//         fileStream.writeByte(0x21);    // Extension introducer
//         fileStream.writeByte(0xff);    // App extension label
//         fileStream.writeByte(11);      // Block size
//         fileStream.writeString("NETSCAPE" + "2.0"); // App id + auth code
//         fileStream.writeByte(3);       // Sub-block size
//         fileStream.writeByte(1);       // Loop sub-block id
//         fileStream.writeInt16(repeat); // Loop count (extra iterations, 0=repeat forever)
//         fileStream.writeByte(0);       // Block terminator
//     }

//         /** Write color table. */
//     function writePalette():Void
//     {
//         fileStream.write(colorTab.view.buffer);
//         var n:Int = (3 * 256) - colorTab.length;

//         for (i in 0...n)
//             fileStream.writeByte(0);
//     }

//     /** Encodes and writes pixel data. */
//     function writePixels():Void
//     {
//         lzwEncoder.reset(indexedPixels, colorDepth);
//         lzwEncoder.encode(fileStream);
//     }

    /** Clamp a value between a and b and return the clamped version */
    static inline public function clamp(value:Float, a:Float, b:Float):Float
    {
        return ( value < a ) ? a : ( ( value > b ) ? b : value );
    }

}


typedef GifFrame = {

        /** Width of the frame */
    var width: Int;
        /** Height of the frame */
    var height: Int;
        /** Delay of the frame in seconds. This value gets floored
            when encoded due to gif format requirements. If this value is negative,
            the default encoder frame rate will be used. */
    var delay: Float;

        /** Pixels data in unsigned bytes, rgb format */
    var data:UInt8Array;

}
