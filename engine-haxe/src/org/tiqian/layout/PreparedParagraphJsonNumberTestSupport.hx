package org.tiqian.layout;

import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphJsonNumberTestSupport {
    public static function rec(name:String):Void
        new TestTraceRecorder("PreparedParagraphJsonNumberTest").section(name);

    public static function eq(expected:String, value:Float):Void
        TracedAssertions.assertEqualsString(expected, PreparedParagraphFns.ecmaJsonNumber(value));
}
