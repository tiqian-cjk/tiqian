package org.tiqian.font;

using std.Functional;

@:dataClass class FontRequest {
    public final preferredFamilies:std.ReadOnlyArray<String>;
    public final locale:String;
    public final role:FontRole;

    public function new(preferredFamilies:std.ReadOnlyArray<String>, locale:String, role:FontRole) {
        this.preferredFamilies = preferredFamilies;
        this.locale = locale;
        this.role = role;
    }
}

@:dataClass class FontCandidate {
    public final key:String;
    public final family:String;
    public final role:FontRole;

    public function new(key:String, family:String, role:FontRole) {
        this.key = key;
        this.family = family;
        this.role = role;
    }
}

@:dataClass class FontDecision {
    public final range:org.tiqian.core.TextRange;
    public final candidate:FontCandidate;
    public final role:FontRole;
    public final reason:String;

    public function new(range:org.tiqian.core.TextRange, candidate:FontCandidate, role:FontRole, reason:String) {
        this.range = range;
        this.candidate = candidate;
        this.role = role;
        this.reason = reason;
    }
}

interface FallbackResolver {
    function resolve(text:String, range:org.tiqian.core.TextRange, request:FontRequest):FontDecision;
}

class FontRoleFns {
    /**
     * Only real Latin text uses the Latin face. Symbol / Emoji / Unknown fall back to the
     * CJK face, so e.g. a missing glyph renders as a full-em 字身框 豆腐 (consistent with
     * CJK body) instead of a Latin half-width box — and measure == draw either way.
     */
    @:extension
    public static function usesLatinFace(role:FontRole):Bool
        return role == LatinText;

    /** Overload for callers that only hold the serialized role name (LayoutResult dumps). */
    @:topLevel
    public static function fontRoleNameUsesLatinFace(roleName:Null<String>):Bool {
        if (roleName == null)
            return false;
        final values:Array<FontRole> = Type.allEnums(FontRole);
        return values.any(value -> Type.enumConstructor(value) == roleName && usesLatinFace(value));
    }
}
