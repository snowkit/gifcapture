package moments.encoder;
import snow.api.buffers.Int32Array;
import snow.api.buffers.Uint8Array;

class NeuQuant {
	static var netsize:Int = 256; // Number of colours used

    // Four primes near 500 - assume no image has a length so large that it is divisible by all four primes
    static var prime1:Int = 499;
    static var prime2:Int = 491;
    static var prime3:Int = 487;
    static var prime4:Int = 503;

    static var minpicturebytes:Int = (3 * prime4); // Minimum size for input image

    // Network Definitions
    static var maxnetpos:Int = (netsize - 1);
    static var netbiasshift:Int = 4; // Bias for colour values
    static var ncycles:Int = 100; // No. of learning cycles

    // Defs for freq and bias
    static var intbiasshift:Int = 16; // Bias for fractions
    static var intbias:Int = (1 << intbiasshift);
    static var gammashift:Int = 10; // Gamma = 1024
    static var gamma:Int = (1 << gammashift);
    static var betashift:Int = 10;
    static var beta:Int = (intbias >> betashift); // Beta = 1/1024
    static var betagamma:Int = (intbias << (gammashift - betashift));

    // Defs for decreasing radius factor
    static var initrad:Int = (netsize >> 3); // For 256 cols, radius starts
    static var radiusbiasshift:Int = 6; // At 32.0 biased by 6 bits
    static var radiusbias:Int = (1 << radiusbiasshift);
    static var initradius:Int = (initrad * radiusbias); // And decreases by a
    static var radiusdec:Int = 30; // Factor of 1/30 each cycle

    // Defs for decreasing alpha factor
    static var alphabiasshift:Int = 10; /* alpha starts at 1.0 */
    static var initalpha:Int = (1 << alphabiasshift);

    var alphadec:Int; // Biased by 10 bits

    // Radbias and alpharadbias used for radpower calculation
    static var radbiasshift:Int = 8;
    static var radbias:Int = (1 << radbiasshift);
    static var alpharadbshift:Int = (alphabiasshift + radbiasshift);
    static var alpharadbias:Int = (1 << alpharadbshift);

    // Types and Global Variables
    var thepicture:Uint8Array; // The input image itself
    var lengthcount:Int; // Lengthcount = H*W*3
    var samplefac:Int; // Sampling factor 1..30
    var network:Array<Array<Int>>; // The network itself - [netsize][4] //:todo: Convert to flat Int32Array?
    var netindex:Int32Array; // For network lookup - really 256
    var bias:Int32Array; // Bias and freq arrays for learning
    var freq:Int32Array;
    var radpower:Int32Array; // Radpower for precomputation

    // Initialize network in range (0,0,0) to (255,255,255) and set parameters
    public function new(thepic:Uint8Array, len:Int, sample:Int)
    {
        netindex = new Int32Array(256);
        bias = new Int32Array(netsize);
        freq = new Int32Array(netsize);
        radpower = new Int32Array(initrad);
        var p:Array<Int>;

        thepicture = thepic;
        lengthcount = len;
        samplefac = sample;

        network = [for (i in 0...netsize) []];
        for (i in 0...netsize)
        {
            network[i] = [for (j in 0...4) 0];
            p = network[i];
            p[0] = p[1] = p[2] = Std.int((i << (netbiasshift + 8)) / netsize);
            freq[i] = Std.int(intbias / netsize); // 1 / netsize
            bias[i] = 0;
        }
    }

    public function ColorMap():Uint8Array
    {
        var map = new Uint8Array(3 * netsize);
        var index:Array<Int> = [for (i in 0...netsize) 0];

        for (i in 0...netsize)
            index[network[i][3]] = i;

        var k:Int = 0;
        for (i in 0...netsize)
        {
            var j = index[i];
            map[k++] = network[j][0];
            map[k++] = network[j][1];
            map[k++] = network[j][2];
        }

        return map;
    }

    // Insertion sort of network and building of netindex[0..255] (to do after unbias)
    public function Inxbuild():Void
    {
        var i:Int;
        var j:Int;
        var smallpos:Int;
        var smallval:Int;
        var p:Array<Int>;
        var q:Array<Int>;
        var previouscol:Int;
        var startpos:Int;

        previouscol = 0;
        startpos = 0;

        for (i in 0...netsize)
        {
            p = network[i];
            smallpos = i;
            smallval = p[1]; // Index on g

            // Find smallest in i..netsize-1
            for (j in (i + 1)...netsize)
            {
                q = network[j];
                if (q[1] < smallval)
                {
                    smallpos = j;
                    smallval = q[1]; // Index on g
                }
            }

            q = network[smallpos];

            // Swap p (i) and q (smallpos) entries
            if (i != smallpos)
            {
                j = q[0];
                q[0] = p[0];
                p[0] = j;
                j = q[1];
                q[1] = p[1];
                p[1] = j;
                j = q[2];
                q[2] = p[2];
                p[2] = j;
                j = q[3];
                q[3] = p[3];
                p[3] = j;
            }

            // Smallval entry is now in position i
            if (smallval != previouscol)
            {
                netindex[previouscol] = (startpos + i) >> 1;

                for (j in (previouscol + 1)...smallval)
                    netindex[j] = i;

                previouscol = smallval;
                startpos = i;
            }
        }

        netindex[previouscol] = (startpos + maxnetpos) >> 1;

        for (j in (previouscol + 1)...256)
            netindex[j] = maxnetpos;
    }

    // Main Learning Loop
    public function Learn():Void
    {
        var i:Int;
        var j:Int;
        var b:Int;
        var g:Int;
        var r:Int;
        var radius:Int;
        var rad:Int;
        var alpha:Int;
        var step:Int;
        var delta:Int;
        var samplepixels:Int;
        
        var p:Uint8Array;
        var pix:Int;
        var lim:Int;

        if (lengthcount < minpicturebytes)
            samplefac = 1;

        alphadec = 30 + Std.int((samplefac - 1) / 3);
        p = thepicture;
        pix = 0;
        lim = lengthcount;
        samplepixels = Std.int(lengthcount / (3 * samplefac));
        delta = Std.int(samplepixels / ncycles);
        alpha = initalpha;
        radius = initradius;

        rad = radius >> radiusbiasshift;

        if (rad <= 1)
            rad = 0;

        for (i in 0...rad)
            radpower[i] = Std.int(alpha * (((rad * rad - i * i) * radbias) / (rad * rad)));

        if (lengthcount < minpicturebytes)
        {
            step = 3;
        }
        else if ((lengthcount % prime1) != 0)
        {
            step = 3 * prime1;
        }
        else
        {
            if ((lengthcount % prime2) != 0)
            {
                step = 3 * prime2;
            }
            else
            {
                if ((lengthcount % prime3) != 0)
                    step = 3 * prime3;
                else
                    step = 3 * prime4;
            }
        }

        i = 0;
        while (i < samplepixels)
        {
            b = (p[pix + 0] & 0xff) << netbiasshift;
            g = (p[pix + 1] & 0xff) << netbiasshift;
            r = (p[pix + 2] & 0xff) << netbiasshift;
            j = Contest(b, g, r);

            Altersingle(alpha, j, b, g, r);

            if (rad != 0)
                Alterneigh(rad, j, b, g, r); // Alter neighbours

            pix += step;

            if (pix >= lim)
                pix -= lengthcount;

            i++;

            if (delta == 0)
                delta = 1;

            if (i % delta == 0)
            {
                alpha -= Std.int(alpha / alphadec);
                radius -= Std.int(radius / radiusdec);
                rad = radius >> radiusbiasshift;

                if (rad <= 1)
                    rad = 0;

                for (j in 0...rad)
                    radpower[j] = Std.int(alpha * (((rad * rad - j * j) * radbias) / (rad * rad)));
            }
        }
    }

    // Search for BGR values 0..255 (after net is unbiased) and return colour index
    public function Map(b:Int, g:Int, r:Int):Int
    {
        var i:Int;
        var j:Int;
        var dist:Int;
        var a:Int;
        var bestd:Int;
        var p:Array<Int>;
        var best:Int;

        bestd = 1000; // Biggest possible dist is 256*3
        best = -1;
        i = netindex[g]; // Index on g
        j = i - 1; // Start at netindex[g] and work outwards

        while ((i < netsize) || (j >= 0))
        {
            if (i < netsize)
            {
                p = network[i];
                dist = p[1] - g; // Inx key

                if (dist >= bestd)
                {
                    i = netsize; // Stop iter
                }
                else
                {
                    i++;

                    if (dist < 0)
                        dist = -dist;

                    a = p[0] - b;

                    if (a < 0)
                        a = -a;

                    dist += a;

                    if (dist < bestd)
                    {
                        a = p[2] - r;

                        if (a < 0)
                            a = -a;

                        dist += a;

                        if (dist < bestd)
                        {
                            bestd = dist;
                            best = p[3];
                        }
                    }
                }
            }

            if (j >= 0)
            {
                p = network[j];
                dist = g - p[1]; // Inx key - reverse dif

                if (dist >= bestd)
                {
                    j = -1; // Stop iter
                }
                else
                {
                    j--;

                    if (dist < 0)
                        dist = -dist;

                    a = p[0] - b;

                    if (a < 0)
                        a = -a;

                    dist += a;

                    if (dist < bestd)
                    {
                        a = p[2] - r;

                        if (a < 0)
                            a = -a;

                        dist += a;

                        if (dist < bestd)
                        {
                            bestd = dist;
                            best = p[3];
                        }
                    }
                }
            }
        }

        return best;
    }

    public function Process():Uint8Array
    {
        Learn();
        Unbiasnet();
        Inxbuild();
        return ColorMap();
    }

    // Unbias network to give byte values 0..255 and record position i to prepare for sort
    public function Unbiasnet():Void
    {
        for (i in 0...netsize)
        {
            network[i][0] >>= netbiasshift;
            network[i][1] >>= netbiasshift;
            network[i][2] >>= netbiasshift;
            network[i][3] = i; // Record colour no
        }
    }

    // Move adjacent neurons by precomputed alpha*(1-((i-j)^2/[r]^2)) in radpower[|i-j|]
    function Alterneigh(rad:Int, i:Int, b:Int, g:Int, r:Int):Void
    {
        var j:Int;
        var k:Int;
        var lo:Int;
        var hi:Int;
        var a:Int;
        var m:Int;
        
        var p:Array<Int>;

        lo = i - rad;

        if (lo < -1)
            lo = -1;

        hi = i + rad;

        if (hi > netsize)
            hi = netsize;

        j = i + 1;
        k = i - 1;
        m = 1;

        while ((j < hi) || (k > lo))
        {
            a = radpower[m++];

            if (j < hi)
            {
                p = network[j++];
                p[0] -= Std.int((a * (p[0] - b)) / alpharadbias);
                p[1] -= Std.int((a * (p[1] - g)) / alpharadbias);
                p[2] -= Std.int((a * (p[2] - r)) / alpharadbias);
            }

            if (k > lo)
            {
                p = network[k--];
                p[0] -= Std.int((a * (p[0] - b)) / alpharadbias);
                p[1] -= Std.int((a * (p[1] - g)) / alpharadbias);
                p[2] -= Std.int((a * (p[2] - r)) / alpharadbias);
            }
        }
    }

    // Move neuron i towards biased (b,g,r) by factor alpha
    function Altersingle(alpha:Int, i:Int, b:Int, g:Int, r:Int):Void
    {
        /* Alter hit neuron */
        var n:Array<Int> = network[i];
        n[0] -= Std.int((alpha * (n[0] - b)) / initalpha);
        n[1] -= Std.int((alpha * (n[1] - g)) / initalpha);
        n[2] -= Std.int((alpha * (n[2] - r)) / initalpha);
    }

    // Search for biased BGR values
    function Contest(b:Int, g:Int, r:Int):Int
    {
        // Finds closest neuron (min dist) and updates freq
        // Finds best neuron (min dist-bias) and returns position
        // For frequently chosen neurons, freq[i] is high and bias[i] is negative
        // bias[i] = gamma*((1/netsize)-freq[i])

        var i:Int;
        var dist:Int;
        var a:Int;
        var biasdist:Int;
        var betafreq:Int;
        var bestpos:Int;
        var bestbiaspos:Int;
        var bestd:Int;
        var bestbiasd:Int;
        var n:Array<Int>;

        bestd = ~(1 << 31);
        bestbiasd = bestd;
        bestpos = -1;
        bestbiaspos = bestpos;

        for (i in 0...netsize)
        {
            n = network[i];
            dist = n[0] - b;

            if (dist < 0)
                dist = -dist;

            a = n[1] - g;

            if (a < 0)
                a = -a;

            dist += a;
            a = n[2] - r;

            if (a < 0)
                a = -a;

            dist += a;

            if (dist < bestd)
            {
                bestd = dist;
                bestpos = i;
            }

            biasdist = dist - ((bias[i]) >> (intbiasshift - netbiasshift));

            if (biasdist < bestbiasd)
            {
                bestbiasd = biasdist;
                bestbiaspos = i;
            }

            betafreq = (freq[i] >> betashift);
            freq[i] -= betafreq;
            bias[i] += (betafreq << gammashift);
        }

        freq[bestpos] += beta;
        bias[bestpos] -= betagamma;
        return bestbiaspos;
    }
}