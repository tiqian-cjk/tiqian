package org.tiqian.test.trace;

private typedef MkdirOptions = {
    final recursive:Bool;
}

@:jsRequire("node:fs")
private extern class NodeFileSystem {
    static function mkdirSync(path:String, options:MkdirOptions):Void;
    static function writeFileSync(path:String, text:String, encoding:String):Void;
}

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
        NodeFileSystem.mkdirSync(directory, {recursive: true});
        NodeFileSystem.writeFileSync(directory + "/" + className + ".txt", text, "utf8");
    }
}
