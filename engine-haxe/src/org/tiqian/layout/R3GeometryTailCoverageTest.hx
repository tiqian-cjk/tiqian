package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class R3GeometryTailCoverageTest {
    @:test public static function attachedReferenceAtSourceEndLaysOutWithoutVirtualBoundary():Void {
        final t = new TestTraceRecorder("R3GeometryTailCoverageTest");
        t.section("attachedReferenceAtSourceEndLaysOutWithoutVirtualBoundary");
        final text = "正文：“内容·[1]";
        final a = 7;
        final r = R3GeometryTailCoverageTestSupport.layout(text, 320, null, [
            new TextSpan(new TextRange(a, a + 3), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
        ]);
        var no = true;
        for (i in 0...r.debug.spacingDecisions.length)
            if (StringTools.startsWith(r.debug.spacingDecisions[i].reason, "AttachedInlineVirtual"))
                no = false;
        TracedAssertions.assertTrue(no);
        var collapse = false;
        for (i in 0...r.debug.spacingDecisions.length)
            if (r.debug.spacingDecisions[i].leftChar == "："
                && r.debug.spacingDecisions[i].rightChar == "“"
                && r.debug.spacingDecisions[i].reduction > 0)
                collapse = true;
        TracedAssertions.assertTrue(collapse);
    }

    @:test public static function centeredInkPunctuationKeepsPairedGlue():Void {
        final t = new TestTraceRecorder("R3GeometryTailCoverageTest");
        t.section("centeredInkPunctuationKeepsPairedGlue");
        final wide = R3GeometryTailCoverageTestSupport.layout("中·文", 320, null, null, null, R3GeometryTailCoverageTestSupport.centeredInkShaper());
        TracedAssertions.assertEqualsInt(1, wide.lines.length);
        final tight = R3GeometryTailCoverageTestSupport.layout("文·本，内容。", 60, null, null, null, R3GeometryTailCoverageTestSupport.centeredInkShaper());
        TracedAssertions.assertTrue(tight.lines.length > 1);
    }

    @:test public static function emptyTextProducesNoVisibleLines():Void {
        final t = new TestTraceRecorder("R3GeometryTailCoverageTest");
        t.section("emptyTextProducesNoVisibleLines");
        final r = R3GeometryTailCoverageTestSupport.layout("", 100);
        TracedAssertions.assertTrue(r.lines.length == 0);
    }

    @:test public static function maxLinesCapsVisibleLinesToOne():Void {
        final t = new TestTraceRecorder("R3GeometryTailCoverageTest");
        t.section("maxLinesCapsVisibleLinesToOne");
        final text = "中文排版引擎测试文本，用于验证多行截断行为是否正确工作并继续延伸。";
        final u = R3GeometryTailCoverageTestSupport.layout(text, 64);
        TracedAssertions.assertTrue(u.lines.length > 1, "fixture must wrap without the cap");
        final c = R3GeometryTailCoverageTestSupport.layout(text, 64, 1);
        TracedAssertions.assertEqualsInt(1, c.lines.length);
    }

    @:test public static function pureLatinParagraphStillProducesLines():Void {
        final t = new TestTraceRecorder("R3GeometryTailCoverageTest");
        t.section("pureLatinParagraphStillProducesLines");
        final r = R3GeometryTailCoverageTestSupport.layout("hello justified world", 96);
        TracedAssertions.assertTrue(r.lines.length > 0);
        TracedAssertions.assertTrue(r.lines[0].naturalWidth > 0);
    }

    @:test public static function rubyBaseRangeCrossingClusterBoundariesIsSkipped():Void {
        final t = new TestTraceRecorder("R3GeometryTailCoverageTest");
        t.section("rubyBaseRangeCrossingClusterBoundariesIsSkipped");
        final r = R3GeometryTailCoverageTestSupport.layout("中文测试", 320, null, null, [
            new RubySpan(new TextRange(0, 2), "zhōng", [], RubyKind.Pinyin),
            new RubySpan(new TextRange(1, 3), "wén", [], RubyKind.Pinyin)
        ]);
        TracedAssertions.assertEqualsInt(2, r.debug.rubyDecisions.length);
    }

    @:test public static function spaceRunsResolveBothWideNarrowOrders():Void {
        final t = new TestTraceRecorder("R3GeometryTailCoverageTest");
        t.section("spaceRunsResolveBothWideNarrowOrders");
        final a = R3GeometryTailCoverageTestSupport.layout("中文 abc", 320);
        TracedAssertions.assertEqualsInt(1, a.lines.length);
        TracedAssertions.assertTrue(a.lines[0].naturalWidth > 0);
        final b = R3GeometryTailCoverageTestSupport.layout("abc 中文", 320);
        TracedAssertions.assertEqualsInt(1, b.lines.length);
        TracedAssertions.assertTrue(b.lines[0].naturalWidth > 0);
    }
}
