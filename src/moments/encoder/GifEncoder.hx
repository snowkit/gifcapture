package moments.encoder;
import luxe.utils.Maths;
import snow.api.buffers.Uint8Array;
import sys.io.File;
import sys.io.FileOutput;

class GifEncoder {
    var Width:Int;
    var Height:Int;
    var Repeat:Int = -1;                  // -1: no repeat, 0: infinite, >0: repeat count
    var FrameDelay:Int = 0;               // Frame delay (milliseconds)
    var HasStarted:Bool = false;          // Ready to output frames
    var FileStream:FileOutput;

    var CurrentFrame:GifFrame;
    var IndexedPixels:Uint8Array;             // Converted frame indexed to palette
    var ColorDepth:Int;                   // Number of bit planes
    var ColorTab:Uint8Array;                  // RGB palette
    var UsedEntry:Array<Bool>;            // Active palette entries
    var PaletteSize:Int = 7;              // Color table size (bits-1)
    var DisposalCode:Int = -1;            // Disposal code (-1 = use default)
    var ShouldCloseStream:Bool = false;   // Close stream when finished
    var IsFirstFrame:Bool = true;
    var IsSizeSet:Bool = false;           // If false, get size from first frame
    var SampleInterval:Int = 10;          // Default sample interval for quantizer

    /// <summary>
    /// Constructor with the number of times the set of GIF frames should be played.
    /// </summary>
    /// <param name="repeat">Default is -1 (no repeat); 0 means play indefinitely</param>
    /// <param name="quality">Sets quality of color quantization (conversion of images to
    /// the maximum 256 colors allowed by the GIF specification). Lower values (minimum = 1)
    /// produce better colors, but slow processing significantly. Higher values will speed
    /// up the quantization pass at the cost of lower image quality (maximum = 100).</param>
    public function new(repeat:Int = -1, quality:Int = 10)
    {
        if (repeat >= 0)
            Repeat = repeat;
        SampleInterval = Std.int(Maths.clamp(quality, 1, 100));
        UsedEntry = [for (i in 0...256) false];
    }

    /// <summary>
    /// Sets the delay time between each frame, or changes it for subsequent frames (applies
    /// to last frame added).
    /// </summary>
    /// <param name="ms">Delay time in milliseconds</param>
    public function SetDelay(ms:Int):Void
    {
        FrameDelay = Math.round(ms / 10);
    }

    /// <summary>
    /// Sets frame rate in frames per second. Equivalent to <code>SetDelay(1000/fps)</code>.
    /// </summary>
    /// <param name="fps">Frame rate</param>
    public function SetFrameRate(fps:Float):Void
    {
        if (fps > 0)
            FrameDelay = Math.round(100 / fps);
    }

    /// <summary>
    /// Adds next GIF frame. The frame is not written immediately, but is actually deferred
    /// until the next frame is received so that timing data can be inserted. Invoking
    /// <code>Finish()</code> flushes all frames.
    /// </summary>
    /// <param name="frame">GifFrame containing frame to write.</param>
    public function AddFrame(frame:GifFrame):Void
    {
        if (frame == null)
            throw "Can't add a null frame to the gif.";

        if (!HasStarted)
            throw "Call Start() before adding frames to the gif.";

        // Use first frame's size
        if (!IsSizeSet)
            SetSize(frame.Width, frame.Height);

        CurrentFrame = frame;
        AnalyzePixels();

        if (IsFirstFrame)
        {
            WriteLSD();
            WritePalette();

            if (Repeat >= 0)
                WriteNetscapeExt();
        }

        WriteGraphicCtrlExt();
        WriteImageDesc();

        if (!IsFirstFrame)
            WritePalette();

        WritePixels();
        IsFirstFrame = false;
    }

    /// <summary>
    /// Initiates GIF file creation on the given stream. The stream is not closed automatically.
    /// </summary>
    /// <param name="os">OutputStream on which GIF images are written, has to be binary and little endian</param>
    public function Start_Output(os:FileOutput):Void
    {
        if (os == null)
            throw "File output is null.";

        ShouldCloseStream = false;
        FileStream = os;

        try {
            FileStream.writeString("GIF89a"); // header
        }
        catch (e:Dynamic) {
            throw e;
        }
        HasStarted = true;
    }

    /// <summary>
    /// Initiates writing of a GIF file with the specified name. The stream will be handled for you.
    /// </summary>
    /// <param name="file">String containing output file name</param>
    public function Start_File(file:String):Void
    {
        try {
            FileStream = File.write(file);
            Start_Output(FileStream);
            ShouldCloseStream = true;
        }
        catch (e:Dynamic) {
            throw e;
        }
    }

    /// <summary>
    /// Flushes any pending data and closes output file.
    /// If writing to an OutputStream, the stream is not closed.
    /// </summary>
    public function Finish():Void
    {
        if (!HasStarted)
            throw "Can't finish a non-started gif.";

        HasStarted = false;

        try
        {
            FileStream.writeByte(0x3b); // Gif trailer
            FileStream.flush();

            if (ShouldCloseStream)
                FileStream.close();
        }
        catch (e:Dynamic)
        {
            throw e;
        }

        // Reset for subsequent use
        FileStream = null;
        CurrentFrame = null;
        IndexedPixels = null;
        ColorTab = null;
        ShouldCloseStream = false;
        IsFirstFrame = true;
    }

    // Sets the GIF frame size.
    function SetSize(w:Int, h:Int):Void
    {
        Width = w;
        Height = h;
        IsSizeSet = true;
    }

    // Analyzes image colors and creates color map.
    function AnalyzePixels():Void
    {
        var len = CurrentFrame.Data.length;
        var nPix = Std.int(len / 3);
        IndexedPixels = new Uint8Array(nPix);
        var nq = new NeuQuant(CurrentFrame.Data, len, SampleInterval);
        ColorTab = nq.Process(); // Create reduced palette

        // Map image pixels to new palette
        var k:Int = 0;
        for (i in 0...nPix)
        {
            var index = nq.Map(CurrentFrame.Data[k++] & 0xff, CurrentFrame.Data[k++] & 0xff, CurrentFrame.Data[k++] & 0xff);
            UsedEntry[index] = true;
            IndexedPixels[i] = index; //(byte)index; :todo: does this have to be ported, if so, how?
        }

        ColorDepth = 8;
        PaletteSize = 7;
    }

    // Writes Graphic Control Extension.
    function WriteGraphicCtrlExt():Void
    {
        FileStream.writeByte(0x21); // Extension introducer
        FileStream.writeByte(0xf9); // GCE label
        FileStream.writeByte(4);    // Data block size

        // Packed fields
        FileStream.writeByte(0 |     // 1:3 reserved
                             0 |     // 4:6 disposal
                             0 |     // 7   user input - 0 = none
                             0 );    // 8   transparency flag
                               // :todo: Deleted a Convert.toByte, necessary?

        FileStream.writeInt16(FrameDelay); // Delay x 1/100 sec
        FileStream.writeByte(0); // Transparent color index
        FileStream.writeByte(0); // Block terminator
    }

    // Writes Image Descriptor.
    function WriteImageDesc():Void
    {
        FileStream.writeByte(0x2c); // Image separator
        FileStream.writeInt16(0);                // Image position x,y = 0,0
        FileStream.writeInt16(0);
        FileStream.writeInt16(Width);          // image size
        FileStream.writeInt16(Height);

        // Packed fields
        if (IsFirstFrame)
        {
            FileStream.writeByte(0); // No LCT  - GCT is used for first (or only) frame
        }
        else
        {
            // Specify normal LCT
            FileStream.writeByte(0x80 |           // 1 local color table  1=yes
                                    0 |              // 2 interlace - 0=no
                                    0 |              // 3 sorted - 0=no
                                    0 |              // 4-5 reserved
                                    PaletteSize); // 6-8 size of color table
        }
    }

    // Writes Logical Screen Descriptor.
    function WriteLSD():Void
    {
        // Logical screen size
        FileStream.writeInt16(Width);
        FileStream.writeInt16(Height);

        // Packed fields
        FileStream.writeByte(0x80 |           // 1   : global color table flag = 1 (gct used)
                             0x70 |           // 2-4 : color resolution = 7
                             0x00 |           // 5   : gct sort flag = 0
                             PaletteSize); // 6-8 : gct size

        FileStream.writeByte(0); // Background color index
        FileStream.writeByte(0); // Pixel aspect ratio - assume 1:1
    }

    // Writes Netscape application extension to define repeat count.
    function WriteNetscapeExt():Void
    {
        FileStream.writeByte(0x21);    // Extension introducer
        FileStream.writeByte(0xff);    // App extension label
        FileStream.writeByte(11);      // Block size
        FileStream.writeString("NETSCAPE" + "2.0"); // App id + auth code
        FileStream.writeByte(3);       // Sub-block size
        FileStream.writeByte(1);       // Loop sub-block id
        FileStream.writeInt16(Repeat);            // Loop count (extra iterations, 0=repeat forever)
        FileStream.writeByte(0);       // Block terminator
    }

    // Write color table.
    function WritePalette():Void
    {
        FileStream.write(ColorTab.toBytes());
        var n:Int = (3 * 256) - ColorTab.length;

        for (i in 0...n)
            FileStream.writeByte(0);
    }

    // Encodes and writes pixel data.
    function WritePixels():Void
    {
        var encoder = new LzwEncoder(Width, Height, IndexedPixels, ColorDepth);
        encoder.Encode(FileStream);
    }
}