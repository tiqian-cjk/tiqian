package org.tiqian.test.trace;

class TestTracePlatform {
    public static final updateMode:Bool = true;
    public static final doubleArithmetic:Bool = true;

    /**
        The directory the trace writer drops its golden files in. The Haxe
        bundle and the Kotlin bundle derive the same file name from the same
        class name, so they must not share one directory: the Kotlin
        generation entry's own define (`-D kotlin-output`, which Haxe
        exposes to `#if` as `kotlin_output`) selects the Kotlin directory,
        and every other target keeps the Haxe bundle's. Both directories live
        under engine-haxe/out, so each target's traces can coexist and the
        file naming rule (<className>.txt) is unchanged.
    **/
    #if kotlin_output
    public static final directory:String = "engine-haxe/out/kotlin-traces";
    #else
    public static final directory:String = "engine-haxe/out/haxe-traces";
    #end

    public static function writeGolden(className:String, text:String):Void {
        try {
            std.Fs.makeDirs(directory);
            std.Fs.writeText(directory + "/" + className + ".txt", text);
        } catch (e:std.FsException) {
            // Golden writing is best-effort; missing directories are non-fatal.
        }
    }
}