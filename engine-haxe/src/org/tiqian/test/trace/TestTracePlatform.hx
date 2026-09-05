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

    public static function writeGolden(className:String, text:String):Void {
        final directory = "engine-haxe/out/haxe-traces";
        NodeFileSystem.mkdirSync(directory, {recursive: true});
        NodeFileSystem.writeFileSync(directory + "/" + className + ".txt", text, "utf8");
    }
}
