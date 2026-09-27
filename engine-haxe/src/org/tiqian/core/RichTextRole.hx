package org.tiqian.core;

import org.tiqian.core.RichTextRole.Background;
import org.tiqian.core.RichTextRole.Underline;
import org.tiqian.core.RichTextRole.LineThrough;
import org.tiqian.core.RichTextRole.Link;
import org.tiqian.core.RichTextRole.TechnicalInline;
import org.tiqian.core.RichTextRole.InlineCode;

@:sealed
interface RichTextRole {
    function toString():String;
}

// Compose SpanStyle.background, painted as one continuous typographic box per visual line.
class Background implements RichTextRole {
    public static final instance:Background = new Background();

    private function new() {}
}

// Compose TextDecoration.Underline, painted with Tiqian line geometry + skip-ink.
class Underline implements RichTextRole {
    public static final instance:Underline = new Underline();

    private function new() {}
}

// Compose TextDecoration.LineThrough, painted with Tiqian line geometry.
class LineThrough implements RichTextRole {
    public static final instance:LineThrough = new LineThrough();

    private function new() {}
}

// Link source range. The URL/click tag is preserved in the model; link actions remain a
// frontend/accessibility slice, so this role does not imply visual fallback or navigation.
@:dataClass class Link implements RichTextRole {
    public final target:String;

    public function new(target:String)
        this.target = target;
}

// Renderer-owned technical inline range. It participates in the shared progressive technical
// break policy but carries no paint of its own, so adapters can supply a code box, border, or
// fallback presentation without duplicating geometry.
class TechnicalInline implements RichTextRole {
    public static final instance:TechnicalInline = new TechnicalInline();

    private function new() {}
}

// Inline code role authored through Tiqian's builder. Its source is unchanged; the Compose
// bridge also lowers its generic monospace font family via TextSpan.
class InlineCode implements RichTextRole {
    public static final instance:InlineCode = new InlineCode();

    private function new() {}
}
