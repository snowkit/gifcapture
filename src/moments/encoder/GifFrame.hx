package moments.encoder;
import snow.api.buffers.Uint8Array;
typedef GifFrame = {
    var Width:Int;
    var Height:Int;
    //Pixels data in unsigned bytes, rgb format
    var Data:Uint8Array;
}