# gifcapture

A threaded GIF capture recording helper, wrapping the [GIF](https://github.com/snowkit/gif) encoding library into a background thread. Has a max time for fixed length recording, thread safe callbacks for progress and complete state with the gif bytes.

Due to the requirement of threads, this library only works on cpp (maybe neko).
**note** The GIF encoding library this wraps no such requirement.

Created by    
- [Tilman Schmidt](https://github.com/KeyMaster-/) 
- [Sven Bergström](https://github.com/underscorediscovery/)

### Install

`haxelib git gifcapture https://github.com/snowkit/gifcapture.git`

Add as a library dependency to your project.

### Usage

The API is documented with more information and usage.
Create a recorder:

```haxe
capture = new GifCapture(width, height, fps, max_time, GifQuality.High, GifRepeat.Infinite);

    //Listen for progress from the encoder
capture.onprogress = onprogress;
    //Listen for progress completion of the encoder
capture.oncomplete = oncomplete;
```

Start/pause/reset/commit a recording:
Note you can record as much as you like before committing.

```haxe
    // start
recorder.record();
    // stop/pause
recorder.pause();
    // complete
recorder.commit();
```

Add frames, with the haxe.io.UInt8Array of bytes, the delay time for the frame to be shown, and the flippedY flag for whether to flip the frame vertically (common requirement for OpenGL captured bytes).

```haxe
recorder.add_frame(frame_bytes, frame_delay, flippedY);
```

You must call `recorder.update()` to propagate callbacks (frequently, i.e every frame is fine)

```haxe
recorder.update();
```

### Example

See [luxe-gifcapture](https://github.com/underscorediscovery/luxe-gifcapture) `tests/test_luxe/`