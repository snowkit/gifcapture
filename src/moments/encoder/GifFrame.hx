package moments.encoder;
import snow.api.buffers.Uint8Array;
typedef GifFrame = {
    var width:Int;
    var height:Int;
    //Pixels data in unsigned bytes, rgb format
    var data:Uint8Array;
}