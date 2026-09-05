package org.tiqian.core;

import org.tiqian.core.RichTextRole.Background;
import org.tiqian.core.RichTextRole.Underline;
import org.tiqian.core.RichTextRole.LineThrough;
import org.tiqian.core.RichTextRole.Link;
import org.tiqian.core.RichTextRole.TechnicalInline;
import org.tiqian.core.RichTextRole.InlineCode;

@:dataClass
class RichTextSpan {
    public final range:TextRange;
    public final role:RichTextRole;
    public final paint:RichTextPaint;

    public function new(range:TextRange, role:RichTextRole, paint:RichTextPaint) {
        this.range = range;
        this.role = role;
        this.paint = paint;
    }

    @:allow(org.tiqian.core.LayoutQueries)
    private static function sameRole(a:RichTextRole, b:RichTextRole):Bool {
        if (Std.isOfType(a, Link) && Std.isOfType(b, Link))
            return (cast(a, Link)).target == (cast(b, Link)).target;
        if (Std.isOfType(a, Background))
            return Std.isOfType(b, Background);
        if (Std.isOfType(a, Underline))
            return Std.isOfType(b, Underline);
        if (Std.isOfType(a, LineThrough))
            return Std.isOfType(b, LineThrough);
        if (Std.isOfType(a, TechnicalInline))
            return Std.isOfType(b, TechnicalInline);
        return Std.isOfType(a, InlineCode) && Std.isOfType(b, InlineCode);
    }
}
