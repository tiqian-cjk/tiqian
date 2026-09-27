#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
 * Compile-time entry for the layout-dump golden data classes.
 *
 * The Kotlin tree embeds these at build time via generateLayoutDumpGoldens
 * (engine/build/generated/layout-dump-goldens/). The Haxe tree mirrors that
 * channel: this macro reads the golden library synced into
 * engine-haxe/baseline-goldens/ and defines the same data classes with the
 * file contents as function-local string literals. Emission stays inside the
 * ordinary expression rules; no static string field is introduced.
 *
 * The defined classes carry a position under engine-haxe/src so the boring
 * Kotlin emitter's inSourceScope check keeps them; defineType-injected types
 * default to a command-line position and would be silently dropped.
 *
 * The golden library is local-only (gitignored, synced from the Kotlin
 * recordings by the curator). A tree without it fails here with the path
 * named below.
 */
class GoldenDataMacros {
    static final sourcePosFile = "engine-haxe/src/org/tiqian/layout/LayoutDumpGoldenData.hx";

    public static function init():Void {
        defineDumpMapClass("LayoutDumpGoldens", "engine-haxe/baseline-goldens/layout-dumps");
        defineDumpMapClass("RecordedLayoutDumpGoldens", "engine-haxe/baseline-goldens/layout-dumps-recorded");
        defineEvidenceJsonClass();
    }

    static function defineDumpMapClass(name:String, dir:String):Void {
        final entries = readDumpEntries(dir);
        final stmts:Array<Expr> = [];
        final builder = macro final b = std.SortedMap.builder();
        stmts.push(builder);
        for (entry in entries) {
            final id = entry.id;
            final content = entry.content;
            stmts.push(macro b.put($v{id}, $v{content}));
        }
        stmts.push(macro return b.build());
        defineClass(name, [
            {
                name: "byId",
                access: [AStatic, APublic],
                pos: macroPos(),
                kind: FFun({
                    args: [],
                    ret: null,
                    expr: {expr: EBlock(stmts), pos: macroPos()}
                })
            }
        ]);
    }

    static function defineEvidenceJsonClass():Void {
        final path = "engine-haxe/baseline-goldens/shaping-evidence.json";
        final content = readTextFile(path);
        defineClass("RecordedShapingEvidenceData", [
            {
                name: "evidenceJson",
                access: [AStatic, APublic],
                pos: macroPos(),
                kind: FFun({
                    args: [],
                    ret: null,
                    expr: macro return $v{content}
                })
            }
        ]);
    }

    static function readDumpEntries(dir:String):Array<{id:String, content:String}> {
        if (!sys.FileSystem.exists(dir)) {
            Context.fatalError('Golden data directory not found: $dir (sync it from the Kotlin recordings)', macroPos());
        }
        final names = sys.FileSystem.readDirectory(dir);
        names.sort(function(a:String, b:String):Int {
            return a < b ? -1 : (a > b ? 1 : 0);
        });
        final entries:Array<{id:String, content:String}> = [];
        for (name in names) {
            if (!StringTools.endsWith(name, ".txt")) {
                continue;
            }
            final id = name.substring(0, name.length - 4);
            entries.push({id: id, content: readTextFile(dir + "/" + name)});
        }
        if (entries.length == 0) {
            Context.fatalError('Golden data directory holds no .txt entries: $dir', macroPos());
        }
        return entries;
    }

    static function readTextFile(path:String):String {
        return try {
            sys.io.File.getContent(path);
        } catch (e:Dynamic) {
            Context.fatalError('Failed to read golden data file $path: $e', macroPos());
        }
    }

    static function defineClass(name:String, fields:Array<Field>):Void {
        Context.defineType({
            pack: ["org", "tiqian", "layout"],
            name: name,
            pos: macroPos(),
            kind: TDClass(),
            fields: fields
        });
    }

    static function macroPos():Position {
        return Context.makePosition({file: sourcePosFile, min: 0, max: 0});
    }
}
#end
