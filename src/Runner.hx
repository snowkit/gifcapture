#if cpp
    import cpp.vm.Thread;
    import cpp.vm.Deque;
#elseif neko
    import neko.vm.Thread;
    import neko.vm.Deque;
#end

typedef VoidFunc = Void->Void;
typedef VoidFuncQueue = Deque<VoidFunc>;

class Runner {

    public static var primary : Thread;

    static var queue : VoidFuncQueue;

        /** Call this on your thread to make primary,
            the calling thread will be used for callbacks. */
    public static function init() {
        queue = new VoidFuncQueue();
        primary = Thread.current();
    }

        /** Call this on the primary manually,
            Returns the number of callbacks called. */
    public static function run() : Int {

        var more = true;
        var count = 0;

        while(more) {
            var item = queue.pop(false);
            if(item != null) {
                count++; item(); item = null;
            } else {
                more = false; break;
            }
        }

        return count;

    } //process

        /** Call a function on the primary thread without waiting or blocking.
            If you want return values see call_primary_ret */
    public static function call_primary( _fn:Void->Void ) {

        queue.push(_fn);

    } //call_primary

        /** Call a function on the primary thread and wait for the return value.
            This will block the calling thread for a maximum of _timeout, default to 0.1s.
            To call without a return or blocking, use call_primary */
    public static function call_primary_ret<T>( _fn:Void->T, _timeout:Float=0.1 ) : Null<T> {

        trace('calling on main with lock (${_timeout}s timeout)');

        var res:T = null;
        var start = Luxe.time;
        var lock = new cpp.vm.Lock();

            //add to main to call this
        queue.push(function() {
            res = _fn();
            lock.release();
        });

            //wait for the lock release or timeout
        lock.wait(_timeout);
            //measure it for reference
        trace('unlocked after ${Luxe.time - start}');

            //clean up
        lock = null;
            //return result
        return res;

    } //call_primary_ret

    public static function thread( fn:VoidFunc ) : Thread {
        return Thread.create( fn );
    }

} //Runner