package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.WidthIndependentAnnotationCache.LruWidthIndependentAnnotationCache;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationKey;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationCacheFns;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentParagraphAnnotation;
import org.tiqian.layout.WidthIndependentAnnotationCacheTestSupport;

using std.RecordCopy;

class WidthIndependentAnnotationCacheTest {
    @:test public static function relayoutWithDifferentWidthHitsCacheAndSkipsShaper():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheTest");
        t.section("relayoutWithDifferentWidthHitsCacheAndSkipsShaper");
        final shaper = new CountingTextShaper();
        final cache = new LruWidthIndependentAnnotationCache(64);
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, shaper, null, cache);

        final inputWidth1 = new LayoutInput(new TiqianTextContent("\u63D0\u6920\u662F\u4E00\u4E2A\u9762\u5411\u4E2D\u6587\u6B63\u6587\u7684 CJK \u6BB5\u843D\u5E03\u5C40\u5F15\u64CE\u3002"),
            null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(300));

        TracedAssertions.assertEquals(0, cache.size);
        TracedAssertions.assertEquals(0, shaper.shapeCallCount);

        final result1 = engine.layout(inputWidth1);
        TracedAssertions.assertTrue(result1.lines.length > 0);
        TracedAssertions.assertEquals(1, cache.size);
        final initialShapeCalls = shaper.shapeCallCount;
        TracedAssertions.assertTrue(initialShapeCalls > 0, "Initial layout must shape segments");

        final inputWidth2 = inputWidth1.copy(constraints = new LayoutConstraints(180));
        final result2 = engine.layout(inputWidth2);
        TracedAssertions.assertEquals(initialShapeCalls, shaper.shapeCallCount, "Relayout at new width must reuse cached annotation without shaping");
        TracedAssertions.assertEquals(1, cache.size);

        final inputWidth3 = inputWidth1.copy(constraints = new LayoutConstraints(500));
        final result3 = engine.layout(inputWidth3);
        TracedAssertions.assertEquals(initialShapeCalls, shaper.shapeCallCount, "Relayout at third width must also reuse cached annotation");

        TracedAssertions.assertTrue(result2.lines.length >= result1.lines.length, "Narrower width should have at least as many lines");
        TracedAssertions.assertTrue(result1.lines.length >= result3.lines.length, "Wider width should have fewer or equal lines");
    }

    @:test public static function cachedAndUncachedEnginesProduceIdenticalLayoutResultsAcrossWidths():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheTest");
        t.section("cachedAndUncachedEnginesProduceIdenticalLayoutResultsAcrossWidths");
        final fixtures:Array<String> = [
            "\u63D0\u6920\u662F\u4E00\u4E2A\u9762\u5411\u4E2D\u6587\u6B63\u6587\u7684\u6BB5\u843D\u6392\u7248\u5F15\u64CE\uFF0C\u9075\u5FAA\u4E2D\u6587\u6392\u7248\u9700\u6C42\u89C4\u8303\uFF0C\u652F\u6301\u4E24\u7AEF\u5BF9\u9F50\u4E0E\u6807\u70B9\u6324\u538B\u3002",
            "\u5728\u300A\u4E2D\u6587\u6392\u7248\u9700\u6C42\u300B\uFF08CLREQ\uFF09\u4E2D\uFF0C\u8981\u6C42\u6B63\u6587\u300C\u4E24\u7AEF\u5BF9\u9F50\u300D\uFF1B\u5F53\u9047\u5230\u300E\u6807\u70B9\u7B26\u53F7\u300F\u4E0E\u897F\u6587\uFF08\u5982 OpenType / CSS Grid\uFF09\u6DF7\u6392\u65F6\uFF0C\u5E94\u6B63\u786E\u6267\u884C\u6324\u538B\u4E0E\u63A8\u5165\u63A8\u51FA\u2014\u2014\u5373\u4F7F\u5728 120Hz \u9AD8\u9891\u62D6\u62FD\u4E0B\u4E5F\u662F\u5982\u6B64\uFF01",
            "\u7B2C\u4E00\u884C\u7F29\u8FDB\u4E24\u4E2A\u5B57\u8EAB\u6846\u3002\u6807\u70B9\u7B26\u53F7\u5982\u2026\u2026\u7701\u7565\u53F7\u3001\u7834\u6298\u53F7\u2014\u2014\u4E0D\u5E94\u51FA\u73B0\u5728\u884C\u9996\uFF0C\u9017\u53F7\u3001\u53E5\u53F7\u3002\u4E5F\u4E0D\u5F97\u51FA\u73B0\u5728\u884C\u9996\u3002\u8FD9\u5C31\u662F\u907F\u5934\u5C3E\uFF08Kinsoku\uFF09\u89C4\u5219\u7684\u4E25\u683C\u8981\u6C42\u3002"
        ];

        final cachedEngine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null,
            new LruWidthIndependentAnnotationCache());
        final uncachedEngine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null,
            new NoOpWidthIndependentAnnotationCache());

        final sweepWidths = WidthIndependentAnnotationCacheTestSupport.generateSweepWidths(80, 7.3, 650);
        for (fixture in fixtures) {
            for (width in sweepWidths) {
                final input = new LayoutInput(new TiqianTextContent(fixture), null, new ParagraphStyle(null, null, null, new Ic(2)),
                    new LayoutConstraints(width));
                final expected = uncachedEngine.layout(input);
                final actual = cachedEngine.layout(input);

                TracedAssertions.assertEquals(expected.lines.length, actual.lines.length,
                    "Line count mismatch for fixture at width " + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                for (i in 0...expected.lines.length) {
                    WidthIndependentAnnotationCacheTestSupport.assertEqualsTextRange(expected.lines[i].range, actual.lines[i].range,
                        "Line "
                        + i
                        + " range mismatch at width "
                        + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                    TracedAssertions.assertEqualsFloatTolerance(expected.lines[i].visualWidth, actual.lines[i].visualWidth, 0.001,
                        "Line "
                        + i
                        + " visualWidth mismatch at width "
                        + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                    TracedAssertions.assertEqualsFloatTolerance(expected.lines[i].adjustedWidth, actual.lines[i].adjustedWidth, 0.001,
                        "Line "
                        + i
                        + " adjustedWidth mismatch at width "
                        + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                    TracedAssertions.assertEqualsFloatTolerance(expected.lines[i].naturalWidth, actual.lines[i].naturalWidth, 0.001,
                        "Line "
                        + i
                        + " naturalWidth mismatch at width "
                        + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                    TracedAssertions.assertEqualsFloatTolerance(expected.lines[i].indent, actual.lines[i].indent, 0.001,
                        "Line "
                        + i
                        + " indent mismatch at width "
                        + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                    TracedAssertions.assertEqualsFloatTolerance(expected.lines[i].hangingPunctuationAdvance, actual.lines[i].hangingPunctuationAdvance, 0.001,
                        "Line "
                        + i
                        + " hanging mismatch at width "
                        + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                    TracedAssertions.assertEqualsEnum(expected.lines[i].endReason, actual.lines[i].endReason,
                        "Line "
                        + i
                        + " endReason mismatch at width "
                        + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                }
            }
        }
    }

    @:test public static function reflowFuzzingRandomSequenceProducesExactOutput():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheTest");
        t.section("reflowFuzzingRandomSequenceProducesExactOutput");
        final fixture = "\u63D0\u6920\u6BB5\u843D\u6392\u7248\uFF1A\u4E25\u683C\u9075\u5FAA\u7B80\u4F53\u4E2D\u6587 CLREQ \u89C4\u8303\u3002\u5305\u542B\u201C\u53CC\u5F15\u53F7\u201D\u3001\u2018\u5355\u5F15\u53F7\u2019\u3001\u4EE5\u53CA\uFF08\u62EC\u53F7\uFF09\u4E0E\u3010\u62EC\u53F7\u3011\uFF1B\u6C49\u5B57\u4E0E English words \u6DF7\u6392\u65F6\u81EA\u52A8\u6DFB\u52A0 0.25em \u95F4\u8DDD\uFF0C\u6700\u540E\u4E00\u884C\u4FDD\u6301\u5DE6\u5BF9\u9F50\u3002";
        final cachedEngine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null,
            new LruWidthIndependentAnnotationCache());
        final uncachedEngine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null,
            new NoOpWidthIndependentAnnotationCache());

        final randomSequenceWidths = [
            320.0, 150.0, 480.5, 95.2, 210.0, 600.0, 120.3, 450.0, 180.7, 300.0, 75.0, 520.0, 133.3, 266.6, 399.9, 110.0, 470.0, 195.0, 345.0, 580.0
        ];
        for (width in randomSequenceWidths) {
            final input = new LayoutInput(new TiqianTextContent(fixture), null, new ParagraphStyle(null, null, null, new Ic(2)), new LayoutConstraints(width));
            final expected = uncachedEngine.layout(input);
            final actual = cachedEngine.layout(input);

            TracedAssertions.assertEquals(expected.lines.length, actual.lines.length,
                "Fuzz line count mismatch at width " + WidthIndependentAnnotationCacheTestSupport.floatText(width));
            for (i in 0...expected.lines.length) {
                WidthIndependentAnnotationCacheTestSupport.assertEqualsTextRange(expected.lines[i].range, actual.lines[i].range,
                    "Fuzz line "
                    + i
                    + " range mismatch at width "
                    + WidthIndependentAnnotationCacheTestSupport.floatText(width));
                TracedAssertions.assertEqualsFloatTolerance(expected.lines[i].visualWidth, actual.lines[i].visualWidth, 0.001,
                    "Fuzz line "
                    + i
                    + " width mismatch at width "
                    + WidthIndependentAnnotationCacheTestSupport.floatText(width));
            }
        }
    }

    @:test public static function cacheKeyDistinguishesTypographyDecorationsAndSpans():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheTest");
        t.section("cacheKeyDistinguishesTypographyDecorationsAndSpans");
        final cache = new LruWidthIndependentAnnotationCache();
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null, cache);

        final baseInput = new LayoutInput(new TiqianTextContent("\u4E2D\u897F\u6DF7\u5408\u6392\u7248\u4E0E\u6D4B\u8BD5\u6587\u672C\u3002"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(300));
        engine.layout(baseInput);
        TracedAssertions.assertEquals(1, cache.size);

        final textChanged = baseInput.copy(content = new TiqianTextContent("\u4E2D\u897F\u6DF7\u5408\u6392\u7248\u4E0E\u53D8\u52A8\u6587\u672C\u3002"));
        engine.layout(textChanged);
        TracedAssertions.assertEquals(2, cache.size);

        final fontChanged = baseInput.copy(textStyle = new TextStyle(null, 24));
        engine.layout(fontChanged);
        TracedAssertions.assertEquals(3, cache.size);

        final emphasisChanged = baseInput.copy(decorations = [new DecorationSpan(new TextRange(0, 4), Emphasis)]);
        engine.layout(emphasisChanged);
        TracedAssertions.assertEquals(4, cache.size);

        final rubyChanged = baseInput.copy(rubySpans = [new RubySpan(new TextRange(0, 2), "zh\u014Dngx\u012B", Pinyin)]);
        engine.layout(rubyChanged);
        TracedAssertions.assertEquals(5, cache.size);

        final inlineBoxChanged = baseInput.copy(inlineBoxes = [new InlineBoxSpan(new TextRange(2, 4), 4, 4)]);
        engine.layout(inlineBoxChanged);
        TracedAssertions.assertEquals(6, cache.size);
    }

    @:test public static function lruCacheEvictsOldestEntriesWhenCapacityExceeded():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheTest");
        t.section("lruCacheEvictsOldestEntriesWhenCapacityExceeded");
        final cache = new LruWidthIndependentAnnotationCache(2);
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null, cache);

        final input1 = new LayoutInput(new TiqianTextContent("\u6BB5\u843D\u4E00\u6587\u672C\u5185\u5BB9"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(300));
        final input2 = new LayoutInput(new TiqianTextContent("\u6BB5\u843D\u4E8C\u6587\u672C\u5185\u5BB9"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(300));
        final input3 = new LayoutInput(new TiqianTextContent("\u6BB5\u843D\u4E09\u6587\u672C\u5185\u5BB9"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(300));

        engine.layout(input1);
        engine.layout(input2);
        TracedAssertions.assertEquals(2, cache.size);

        final key1 = WidthIndependentAnnotationCacheTestSupport.annotationKey(input1);
        final key2 = WidthIndependentAnnotationCacheTestSupport.annotationKey(input2);
        TracedAssertions.assertTrue(cache.get(key1) != null);
        TracedAssertions.assertTrue(cache.get(key2) != null);

        engine.layout(input3);
        TracedAssertions.assertEquals(2, cache.size);
        final key3 = WidthIndependentAnnotationCacheTestSupport.annotationKey(input3);
        TracedAssertions.assertTrue(cache.get(key3) != null);
        TracedAssertions.assertTrue(cache.get(key2) != null);
        WidthIndependentAnnotationCacheTestSupport.assertEqualsNullableAnnotation(null, cache.get(key1), "Oldest entry key1 should be evicted");
    }
}

class NoOpWidthIndependentAnnotationCache implements WidthIndependentAnnotationCache {
    public var size(get, never):Int;

    public function new() {}

    private function get_size():Int
        return 0;

    public function get(key:WidthIndependentAnnotationKey):Null<WidthIndependentParagraphAnnotation>
        return null;

    public function put(key:WidthIndependentAnnotationKey, annotation:WidthIndependentParagraphAnnotation):Void {}

    public function clear():Void {}
}
