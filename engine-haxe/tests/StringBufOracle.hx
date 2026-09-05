package;

import js.Syntax;

/** Binds the Haxe standard StringBuf implementation to the boring std name. */
class StringBufOracle {
    private final buffer:StringBuf;

    public function new() {
        buffer = new StringBuf();
    }

    public function add(part:String):Void {
        buffer.add(part);
    }

    public function addChar(codeUnit:Int):Void {
        buffer.addChar(codeUnit);
    }

    public var length(get, never):Int;

    private function get_length():Int {
        return buffer.length;
    }

    public function toString():String {
        return buffer.toString();
    }

    public static function install():Void {
        Syntax.code("globalThis.std = globalThis.std || {}; globalThis.std.StringBuf = {0};", StringBufOracle);
    }
}
