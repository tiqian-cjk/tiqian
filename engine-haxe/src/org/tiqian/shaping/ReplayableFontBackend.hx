package org.tiqian.shaping;

import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError;
import org.tiqian.font.FontRole;
import std.SortedMap;
import std.SortedSet;

/** Stable identity of one physical SFNT face, collection index and variation instance. */
abstract FontFaceId(String) {
    public static function of(value:String):FontFaceId {
        if (value == null || StringTools.trim(value).length == 0)
            throw new TiqianIllegalArgumentException(Message("FontFaceId must not be blank"));
        return cast(value, FontFaceId);
    }

    @:from public static function fromString(value:String):FontFaceId
        return of(value);

    public var value(get, never):String;

    inline function get_value():String
        return this;

    public function toString():String
        return this;
}

class ReplayableFontFaceDescriptor {
    public final id:FontFaceId;
    public final familyAliases:SortedSet<String>;
    public final roles:Array<FontRole>;
    public final weight:Int;
    public final italic:Bool;
    public final collectionIndex:Int;
    public final sourceLabel:String;
    public final variationAxes:SortedMap<String, Float>;

    public function new(id:FontFaceId, familyAliases:SortedSet<String>, roles:Array<FontRole>, sourceLabel:String, ?weight:Int = 400, ?italic:Bool = false,
            ?collectionIndex:Int = 0, ?variationAxes:SortedMap<String, Float>) {
        this.id = id;
        this.familyAliases = familyAliases;
        this.roles = roles;
        this.weight = weight;
        this.italic = italic;
        this.collectionIndex = collectionIndex;
        this.sourceLabel = sourceLabel;
        this.variationAxes = variationAxes == null ? SortedMap.builder().build() : variationAxes;
    }
}

class ReplayableFontFaceRequest {
    public final role:FontRole;
    public final preferredFamilies:Array<String>;
    public final fontSize:Float;
    public final weight:Int;
    public final italic:Bool;
    public final locale:String;
    public final selectionText:String;

    public function new(role:FontRole, preferredFamilies:Array<String>, fontSize:Float, weight:Int, italic:Bool, locale:String, selectionText:String) {
        if (!(fontSize > 0 && Math.isFinite(fontSize)))
            throw new TiqianIllegalArgumentException(Message("fontSize must be positive and finite"));
        this.role = role;
        this.preferredFamilies = preferredFamilies;
        this.fontSize = fontSize;
        this.weight = weight;
        this.italic = italic;
        this.locale = locale;
        this.selectionText = selectionText;
    }
}

class FontBackendCapabilityIssue {
    public final code:String;
    public final detail:String;

    public function new(code:String, detail:String) {
        this.code = code;
        this.detail = detail;
    }
}

class FontBackendCapabilityReport {
    public final backend:String;
    public final sourceKind:String;
    public final faces:Array<ReplayableFontFaceDescriptor>;
    public final issues:Array<FontBackendCapabilityIssue>;

    public function new(backend:String, sourceKind:String, faces:Array<ReplayableFontFaceDescriptor>, ?issues:Array<FontBackendCapabilityIssue>) {
        this.backend = backend;
        this.sourceKind = sourceKind;
        this.faces = faces;
        this.issues = issues == null ? [] : issues;
    }

    public var canReplayFromControlledBytes(get, never):Bool;

    function get_canReplayFromControlledBytes():Bool {
        if (faces.length == 0)
            return false;
        for (issue in issues)
            if (issue.code == "MissingControlledFontFace")
                return false;
        return true;
    }
}

/** Platform-neutral catalog contract shared by shaping, metrics and replay. */
interface ReplayableFontCatalog {
    public var faces(get, never):Array<ReplayableFontFaceDescriptor>;
    public var capabilityReport(get, never):FontBackendCapabilityReport;
    public function resolve(request:ReplayableFontFaceRequest):Null<ReplayableFontFaceDescriptor>;
}
