package gif;

class Timer {
    static var start_map:Map<String, Float>;
    
    public static function init() {
        start_map = new Map();
    }

    public static function start(name:String) {
        start_map.set(name, Sys.time());
    }

    public static function end(name:String) {
        var elapsed = Sys.time() - start_map.get(name);
        trace('$name: $elapsed');
        start_map.remove(name);
    }
}