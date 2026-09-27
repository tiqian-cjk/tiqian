package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class ParagraphLayoutEngineValidationCoverageSupport {
    public static function code(n:Int):String {
        final b = new StringBuf();
        b.addChar(n);
        return b.toString();
    }

    public static function input(?style:ParagraphStyle, ?boxes:Array<InlineBoxSpan>, ?objects:Array<InlineObjectSpan>, ?content:TiqianTextContent):LayoutInput
        return new LayoutInput(content == null ? new TiqianTextContent("甲乙") : content, null, style == null ? new ParagraphStyle() : style,
            new LayoutConstraints(100), null, null, null, boxes, objects);

    public static function obj(?range:TextRange, ?advance:Float, ?ascent:Float, ?descent:Float, ?leading:InlineObjectBoundaryAdjustment,
            ?trailing:InlineObjectBoundaryAdjustment):InlineObjectSpan
        return new InlineObjectSpan(range == null ? new TextRange(0, 1) : range, advance == null ? 10 : advance, ascent == null ? 8 : ascent,
            descent == null ? 2 : descent, leading == null ? new InlineObjectBoundaryAdjustment() : leading,
            trailing == null ? new InlineObjectBoundaryAdjustment() : trailing);

    public static function reject(bad:LayoutInput, fragment:String):Void {
        final e = TracedAssertions.assertFailsWith(null, function():Void {
            new ExplainableStubParagraphLayoutEngine().layout(bad);
        });
        TracedAssertions.assertTrue(e.message.indexOf(fragment) >= 0, e.message);
    }
}
