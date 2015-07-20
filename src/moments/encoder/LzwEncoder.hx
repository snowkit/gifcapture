package moments.encoder;
import snow.api.buffers.Int32Array;
import snow.api.buffers.Uint8Array;

class LzwEncoder {
    static var EOF(default, never):Int = -1;

    var pixAry:Uint8Array;
    var initCodeSize:Int;
    var curPixel:Int;

    // GIFCOMPR.C       - GIF Image compression routines
    //
    // Lempel-Ziv compression based on 'compress'.  GIF modifications by
    // David Rowley (mgardi@watdcsu.waterloo.edu)

    // General DEFINEs

    static var BITS(default, never):Int = 12;

    static var HSIZE(default, never):Int = 5003; // 80% occupancy

    // GIF Image compression - modified 'compress'
    //
    // Based on: compress.c - File compression ala IEEE Computer, June 1984.
    //
    // By Authors:  Spencer W. Thomas      (decvax!harpo!utah-cs!utah-gr!thomas)
    //              Jim McKie              (decvax!mcvax!jim)
    //              Steve Davies           (decvax!vax135!petsd!peora!srd)
    //              Ken Turkowski          (decvax!decwrl!turtlevax!ken)
    //              James A. Woods         (decvax!ihnp4!ames!jaw)
    //              Joe Orost              (decvax!vax135!petsd!joe)

    var n_bits:Int; // number of bits/code
    var maxbits:Int = BITS; // user settable max # bits/code
    var maxcode:Int; // maximum code, given n_bits
    var maxmaxcode:Int = 1 << BITS; // should NEVER generate this code

    var htab:Int32Array;
    var codetab:Int32Array;

    var hsize:Int = HSIZE; // for dynamic table sizing

    var free_ent:Int = 0; // first unused entry

    // block compression parameters -- after all codes are used up,
    // and compression rate changes, start over.
    var clear_flg:Bool = false;

    // Algorithm:  use open addressing double hashing (no chaining) on the
    // prefix code / next character combination.  We do a variant of Knuth's
    // algorithm D (vol. 3, sec. 6.4) along with G. Knott's relatively-prime
    // secondary probe.  Here, the modular division first probe is gives way
    // to a faster exclusive-or manipulation.  Also do block compression with
    // an adaptive reset, whereby the code table is cleared when the compression
    // ratio decreases, but after the table fills.  The variable-length output
    // codes are re-sized at this point, and a special CLEAR code is generated
    // for the decompressor.  Late addition:  construct the table according to
    // file size for noticeable speed improvement on small files.  Please direct
    // questions about this implementation to ames!jaw.

    var g_init_bits:Int;

    var ClearCode:Int;
    var EOFCode:Int;

    // output
    //
    // Output the given code.
    // Inputs:
    //      code:   A n_bits-bit integer.  If == -1, then EOF.  This assumes
    //              that n_bits =< wordsize - 1.
    // Outputs:
    //      Outputs code to the file.
    // Assumptions:
    //      Chars are 8 bits long.
    // Algorithm:
    //      Maintain a BITS character long buffer (so that 8 codes will
    // fit in it exactly).  Use the VAX insv instruction to insert each
    // code in turn.  When the buffer fills up empty it and start over.

    var cur_accum:Int = 0;
    var cur_bits:Int = 0;

    var masks:Array<Int> =
    [
        0x0000,
        0x0001,
        0x0003,
        0x0007,
        0x000F,
        0x001F,
        0x003F,
        0x007F,
        0x00FF,
        0x01FF,
        0x03FF,
        0x07FF,
        0x0FFF,
        0x1FFF,
        0x3FFF,
        0x7FFF,
        0xFFFF ];

    // Number of characters so far in this 'packet'
    var a_count:Int;

    // Define the storage for the packet accumulator
    var accum:Uint8Array;

    //----------------------------------------------------------------------------
    public function new() 
    {
        htab = new Int32Array(HSIZE);
        codetab = new Int32Array(HSIZE);
        accum = new Uint8Array(256);
    }
    
    //Reset the encoder to new pixel data and default values
    public function reset(pixels:Uint8Array, color_depth:Int) { //width and height used to be passed in though they were never used
        pixAry = pixels;
        initCodeSize = Std.int(Math.max(2, color_depth));
        
        maxbits = BITS;
        maxmaxcode = 1 << BITS;
        hsize = HSIZE;
        free_ent = 0;
        clear_flg = false;
        cur_accum = 0;
        cur_bits = 0;
    }

    // Add a character to the end of the current packet, and if it is 254
    // characters, flush the packet to disk.
    function Add(c:UInt, outs:haxe.io.Output):Void
    {
        accum[a_count++] = c;
        if (a_count >= 254)
            Flush(outs);
    }

    // Clear out the hash table

    // table clear for block compress
    function ClearTable(outs:haxe.io.Output):Void
    {
        ResetCodeTable(hsize);
        free_ent = ClearCode + 2;
        clear_flg = true;

        Output(ClearCode, outs);
    }

    // reset code table
    function ResetCodeTable(hsize:Int):Void
    {
        for (i in 0...hsize)
            htab[i] = -1;
    }

    function Compress(init_bits:Int, outs:haxe.io.Output):Void
    {
        var fcode:Int;
        var i:Int /* = 0 */;
        var c:Int;
        var ent:Int;
        var disp:Int;
        var hsize_reg:Int;
        var hshift:Int;

        // Set up the globals:  g_init_bits - initial number of bits
        g_init_bits = init_bits;

        // Set up the necessary values
        clear_flg = false;
        n_bits = g_init_bits;
        maxcode = MaxCode(n_bits);

        ClearCode = 1 << (init_bits - 1);
        EOFCode = ClearCode + 1;
        free_ent = ClearCode + 2;

        a_count = 0; // clear packet

        ent = NextPixel();

        hshift = 0;
        fcode = hsize;
        while (fcode < 65536) {
            ++hshift;
            fcode *= 2;
        }
        
        hshift = 8 - hshift; // set hash code range bound

        hsize_reg = hsize;
        ResetCodeTable(hsize_reg); // clear hash table

        Output(ClearCode, outs);

        while ((c = NextPixel()) != EOF) 
        {
            fcode = (c << maxbits) + ent;
            i = (c << hshift) ^ ent; // xor hashing

            if (htab[i] == fcode) 
            {
                ent = codetab[i];
                continue;
            } 
            else if (htab[i] >= 0) // non-empty slot
            {
                disp = hsize_reg - i; // secondary hash (after G. Knott)
                if (i == 0)
                    disp = 1;
                do 
                {
                    if ((i -= disp) < 0)
                        i += hsize_reg;

                    if (htab[i] == fcode) 
                    {
                        ent = codetab[i];
                        break;
                    }
                } while (htab[i] >= 0);
                if (htab[i] == fcode) continue;
            }
            Output(ent, outs);
            ent = c;
            if (free_ent < maxmaxcode) 
            {
                codetab[i] = free_ent++; // code -> hashtable
                htab[i] = fcode;
            } 
            else
                ClearTable(outs);
        }
        // Put out the final code.
        Output(ent, outs);
        Output(EOFCode, outs);
    }

    //----------------------------------------------------------------------------
    public function Encode( os:haxe.io.Output):Void
    {
        os.writeByte( initCodeSize ); // write "initial code size" byte
        curPixel = 0;
        Compress(initCodeSize + 1, os); // compress and write the pixel data
        os.writeByte(0); // write block terminator
    }

    // Flush the packet to disk, and reset the accumulator
    function Flush(outs:haxe.io.Output):Void
    {
        if (a_count > 0) 
        {
            outs.writeByte(a_count);
            outs.writeBytes(accum.toBytes(), 0, a_count);
            a_count = 0;
        }
    }

    function MaxCode(n_bits:Int):Int
    {
        return (1 << n_bits) - 1;
    }

    //----------------------------------------------------------------------------
    // Return the next pixel from the image
    //----------------------------------------------------------------------------
    function NextPixel():Int
    {
        if (curPixel == pixAry.length)
            return EOF;
        
        curPixel++;
        return pixAry[curPixel - 1] & 0xff;
    }

    function Output(code:Int, outs:haxe.io.Output):Void
    {
        cur_accum &= masks[cur_bits];

        if (cur_bits > 0)
            cur_accum |= (code << cur_bits);
        else
            cur_accum = code;

        cur_bits += n_bits;

        while (cur_bits >= 8) 
        {
            Add(cur_accum & 0xff, outs);
            cur_accum >>= 8;
            cur_bits -= 8;
        }

        // If the next entry is going to be too big for the code size,
        // then increase it, if possible.
        if (free_ent > maxcode || clear_flg) 
        {
            if (clear_flg) 
            {
                maxcode = MaxCode(n_bits = g_init_bits);
                clear_flg = false;
            } 
            else 
            {
                ++n_bits;
                if (n_bits == maxbits)
                    maxcode = maxmaxcode;
                else
                    maxcode = MaxCode(n_bits);
            }
        }

        if (code == EOFCode) 
        {
            // At EOF, write the rest of the buffer.
            while (cur_bits > 0) 
            {
                Add(cur_accum & 0xff, outs);
                cur_accum >>= 8;
                cur_bits -= 8;
            }

            Flush(outs);
        }
    }
}