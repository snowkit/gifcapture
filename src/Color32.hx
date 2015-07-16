package ;

class Color32 { //:todo: probably doesn't have to be a class
    public var r:UInt;
    public var g:UInt;
    public var b:UInt;
    public var a:UInt;
    
    public function new(_r:UInt, _g:UInt, _b:UInt, _a:UInt) {
        r = _r;
        g = _g;
        b = _b;
        a = _a;
    }
}