// Stage-A JS runtime binding for the std.Functional extern set
// (samples/std/Functional.hx declares @:native("__functional_shim")). The Haxe
// test bundle must install the global itself, the same way boring's own test
// collector does (boring src/TestCollector.hx: class JsFunctional and class
// FunctionalOracle). Member bodies mirror those two sources; the specs are
// docs/specs/macros/01-functional-idiom-expansion.md, macros/02 (additions),
// and macros/03 (groupBy). Contract: sortedBy/associate/groupBy keys are Int
// in current use; extend per adopted key type. The core-kotlin gate expands
// all closed-list calls into loops and never runs this oracle.
class FunctionalOracle {
    public static function install():Void {
        js.Syntax.code("globalThis.__functional_shim = { forEach: {0}, associate: {1}, sortedBy: {2}, mapNotNull: {3}, groupBy: {4}, any: {5}, all: {6}, firstOrNull: {7}, sumOfInt: {8}, sumOfFloat: {9}, flatMap: {10} }",
            forEach, associate, sortedBy, mapNotNull, groupBy, any, all, firstOrNull, sumOfInt, sumOfFloat, flatMap);
    }

    private static function forEach(arr:Array<Dynamic>, fn:(Dynamic) -> Void):Void {
        var i:Int = 0;
        while (i < arr.length) {
            fn(arr[i]);
            i += 1;
        }
    }

    // Duplicate keys follow last-wins (macros/01, associate row).
    private static function associate(arr:Array<Dynamic>, fn:(Dynamic) -> {key: Int, value: Dynamic}):std.SortedMap<Int, Dynamic> {
        final builder = std.SortedMap.builder();
        var i:Int = 0;
        while (i < arr.length) {
            final entry = fn(arr[i]);
            builder.put(entry.key, entry.value);
            i += 1;
        }
        return builder.build();
    }

    // Ascending by key, stable on equal keys via index tiebreak (macros/01).
    private static function sortedBy(arr:Array<Dynamic>, keyFn:(Dynamic) -> Int):Array<Dynamic> {
        final decorated:Array<{item:Dynamic, key:Int, idx:Int}> = [];
        var i:Int = 0;
        while (i < arr.length) {
            decorated.push({item: arr[i], key: keyFn(arr[i]), idx: i});
            i += 1;
        }
        decorated.sort(function(a:{item:Dynamic, key:Int, idx:Int}, b:{item:Dynamic, key:Int, idx:Int}):Int {
            if (a.key < b.key)
                return -1;
            if (a.key > b.key)
                return 1;
            return a.idx - b.idx;
        });
        final out:Array<Dynamic> = [];
        i = 0;
        while (i < decorated.length) {
            out.push(decorated[i].item);
            i += 1;
        }
        return out;
    }

    private static function mapNotNull(arr:Array<Dynamic>, fn:(Dynamic) -> Null<Dynamic>):Array<Dynamic> {
        final out:Array<Dynamic> = [];
        var i:Int = 0;
        while (i < arr.length) {
            final value = fn(arr[i]);
            if (value != null)
                out.push(value);
            i += 1;
        }
        return out;
    }

    // Keys ascend; each bucket keeps receiver order (macros/03).
    private static function groupBy(arr:Array<Dynamic>, fn:(Dynamic) -> {key: Int, value: Dynamic}):std.SortedMap<Int, Array<Dynamic>> {
        final builder = std.SortedMap.builder();
        var i:Int = 0;
        while (i < arr.length) {
            final entry = fn(arr[i]);
            var bucket = builder.get(entry.key);
            if (bucket == null) {
                bucket = new Array<Dynamic>();
                builder.put(entry.key, bucket);
            }
            bucket.push(entry.value);
            i += 1;
        }
        return builder.build();
    }

    private static function any(arr:Array<Dynamic>, fn:(Dynamic) -> Bool):Bool {
        var i:Int = 0;
        while (i < arr.length) {
            if (fn(arr[i]))
                return true;
            i += 1;
        }
        return false;
    }

    private static function all(arr:Array<Dynamic>, fn:(Dynamic) -> Bool):Bool {
        var i:Int = 0;
        while (i < arr.length) {
            if (!fn(arr[i]))
                return false;
            i += 1;
        }
        return true;
    }

    private static function firstOrNull(arr:Array<Dynamic>, fn:(Dynamic) -> Bool):Null<Dynamic> {
        var i:Int = 0;
        while (i < arr.length) {
            if (fn(arr[i]))
                return arr[i];
            i += 1;
        }
        return null;
    }

    private static function sumOfInt(arr:Array<Dynamic>, fn:(Dynamic) -> Int):Int {
        var total:Int = 0;
        var i:Int = 0;
        while (i < arr.length) {
            total += fn(arr[i]);
            i += 1;
        }
        return total;
    }

    private static function sumOfFloat(arr:Array<Dynamic>, fn:(Dynamic) -> Float):Float {
        var total:Float = 0.0;
        var i:Int = 0;
        while (i < arr.length) {
            total += fn(arr[i]);
            i += 1;
        }
        return total;
    }

    private static function flatMap(arr:Array<Dynamic>, fn:(Dynamic) -> Array<Dynamic>):Array<Dynamic> {
        final out:Array<Dynamic> = [];
        var i:Int = 0;
        while (i < arr.length) {
            final inner:Array<Dynamic> = fn(arr[i]);
            var j:Int = 0;
            while (j < inner.length) {
                out.push(inner[j]);
                j += 1;
            }
            i += 1;
        }
        return out;
    }
}
