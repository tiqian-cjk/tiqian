package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.WidthIndependentAnnotationCache.LruWidthIndependentAnnotationCache;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationCacheFns;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentParagraphAnnotation;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTestSupport;

using std.RecordCopy;

class WidthIndependentAnnotationCacheCoverageTest {
    @:test public static function lruCacheUpdateExistingKeyAndClear():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("lruCacheUpdateExistingKeyAndClear");
        final cache = new LruWidthIndependentAnnotationCache(2);
        final dummyInput = new LayoutInput(new TiqianTextContent("\u6D4B\u8BD5\u7F13\u5B58"), null, null, new LayoutConstraints(300));
        final key = WidthIndependentAnnotationCacheCoverageTestSupport.key(dummyInput);

        // 1. Initial put
        cache.put(key, WidthIndependentAnnotationCacheCoverageTestSupport.annotationForText("v1"));
        TracedAssertions.assertEqualsInt(1, cache.size);
        TracedAssertions.assertEqualsString("v1", cache.get(key).text);

        // 2. Put existing key (key in map branch)
        cache.put(key, WidthIndependentAnnotationCacheCoverageTestSupport.annotationForText("v2"));
        TracedAssertions.assertEqualsInt(1, cache.size);
        TracedAssertions.assertEqualsString("v2", cache.get(key).text);

        // 3. Put another key
        final key2 = WidthIndependentAnnotationCacheCoverageTestSupport.key(dummyInput.copy(textStyle = new TextStyle(null, 20.0)));
        cache.put(key2, WidthIndependentAnnotationCacheCoverageTestSupport.annotationForText("v3"));
        TracedAssertions.assertEqualsInt(2, cache.size);

        // 4. Put third key to trigger eviction
        final key3 = WidthIndependentAnnotationCacheCoverageTestSupport.key(dummyInput.copy(textStyle = new TextStyle(null, 30.0)));
        cache.put(key3, WidthIndependentAnnotationCacheCoverageTestSupport.annotationForText("v4"));
        TracedAssertions.assertEqualsInt(2, cache.size);
        TracedAssertions.assertNullRendered(cache.get(key) == null, "-");
        TracedAssertions.assertEqualsString("v3", cache.get(key2).text);
        TracedAssertions.assertEqualsString("v4", cache.get(key3).text);

        // 5. Clear
        cache.clear();
        TracedAssertions.assertEqualsInt(0, cache.size);
        TracedAssertions.assertNullRendered(cache.get(key2) == null, "-");
        TracedAssertions.assertNullRendered(cache.get(key3) == null, "-");
    }

    @:test public static function containingItemsAndFirstContainedItemBranches():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("containingItemsAndFirstContainedItemBranches");
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), "aa", "k", 10.0, "aa"),
            new Cluster(new TextRange(2, 5), "bbb", "k", 15.0, "bbb"),
            new Cluster(new TextRange(5, 7), "cc", "k", 10.0, "cc"),
            new Cluster(new TextRange(7, 9), "dd", "k", 10.0, "dd"),
        ];
        final items:Array<TextRange> = [
            new TextRange(0, 2),
            new TextRange(1, 4),
            new TextRange(5, 8),
            new TextRange(10, 12)
        ];

        final contained = WidthIndependentAnnotationCacheCoverageTestSupport.containingItems(clusters, items);
        TracedAssertions.assertEqualsInt(4, contained.length);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=2)", Std.string(contained[0]));
        TracedAssertions.assertNullRendered(contained[1] == null, "-");
        TracedAssertions.assertEqualsRendered("TextRange(start=5, end=8)", Std.string(contained[2]));
        TracedAssertions.assertNullRendered(contained[3] == null, "-");

        final firstContained = WidthIndependentAnnotationCacheCoverageTestSupport.firstContainedItem(clusters, items);
        TracedAssertions.assertEqualsInt(4, firstContained.length);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=2)", Std.string(firstContained[0]));
        TracedAssertions.assertNullRendered(firstContained[1] == null, "-");
        TracedAssertions.assertNullRendered(firstContained[2] == null, "-");
        TracedAssertions.assertNullRendered(firstContained[3] == null, "-");
    }

    @:test public static function prepareWidthIndependentAnnotationBranches():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("prepareWidthIndependentAnnotationBranches");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();

        final input = new LayoutInput(new TiqianTextContent("\u6D4B\u8BD5\u6587\u672C\u3010\u4E2D\u6587\u3011\u4E0EEnglish\uFF0C\u4EE5\u53CA\u6CE8\u97F3\u4E0E\u884C\u5185\u6846\u3002",
            [
            new TextSpan(new TextRange(0, 0), new TextStyle(null, 10.0)),
            new TextSpan(new TextRange(0, 1), new TextStyle(null, 18.0, null, 500)),
            new TextSpan(new TextRange(1, 4), new TextStyle(null, 18.0, null, 500)),
            new TextSpan(new TextRange(4, 8), new TextStyle(null, 14.0, null, 300)),
        ],
            [1, 2, 3, 4, 6],
            [new LineBreakSpan(new TextRange(8, 15),
                LineBreakPolicy.ProgressiveTechnical)],), new TextStyle(null, 16.0, "zh-CN", 400), null, new LayoutConstraints(300),
            null, [
                new DecorationSpan(new TextRange(0, 4), DecorationKind.Emphasis),
                new DecorationSpan(new TextRange(4, 8), DecorationKind.ProperNoun),
            ], [
                new RubySpan(new TextRange(0, 2), "c\u00E8sh\u00EC", null, RubyKind.Pinyin, "zh-Latn"),
                new RubySpan(new TextRange(2, 4), "", null, RubyKind.Pinyin),
                new RubySpan(new TextRange(0, 1), "\u02D9\u3105", null, RubyKind.Bopomofo),
                new RubySpan(new TextRange(0, 1), "\u3106", null, RubyKind.Bopomofo),
                new RubySpan(new TextRange(99, 100), "invalid", null, RubyKind.Bopomofo),
            ], [
                new InlineBoxSpan(new TextRange(15, 17), 4.0, 0.0),
                new InlineBoxSpan(new TextRange(17, 19), 0.0, 4.0),
                new InlineBoxSpan(new TextRange(19, 21), null, null, InlineBoxOuterSpacing.Narrow),
                new InlineBoxSpan(new TextRange(21, 23), 0.0, 0.0, InlineBoxOuterSpacing.Source),
            ], [new InlineObjectSpan(new TextRange(23, 24), 20.0, 12.0, 4.0)],);

        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(annotation != null, annotation == null ? "null" : "WidthIndependentParagraphAnnotation@identity");
        TracedAssertions.assertEqualsFloat(18.0, annotation.fontSizeAt(0));
        TracedAssertions.assertEqualsFloat(14.0, annotation.fontSizeAt(5));
        TracedAssertions.assertEqualsFloat(16.0, annotation.fontSizeAt(24));

        TracedAssertions.assertEqualsInt(800, annotation.bopomofoFontWeightAt(0));
        TracedAssertions.assertEqualsInt(600, annotation.bopomofoFontWeightAt(5));
        TracedAssertions.assertEqualsInt(700, annotation.bopomofoFontWeightAt(24));

        TracedAssertions.assertEqualsFloat(18.0, annotation.styleAt(0).fontSize);
        TracedAssertions.assertEqualsFloat(18.0, annotation.styleAt(3).fontSize);
        TracedAssertions.assertEqualsFloat(14.0, annotation.styleAt(4).fontSize);
        TracedAssertions.assertEqualsFloat(14.0, annotation.styleAt(7).fontSize);
        TracedAssertions.assertEqualsFloat(16.0, annotation.styleAt(8).fontSize);
        TracedAssertions.assertEqualsFloat(16.0, annotation.styleAt(25).fontSize);

        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
        TracedAssertions.assertTrue(prep.rubyAndBopomofoSpread.size() > 0);
    }

    @:test public static function lineLengthGridBodyAlignmentBranches():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("lineLengthGridBodyAlignmentBranches");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u4E03\u516B\u4E5D\u5341";

        for (align in [LastLineAlignment.Start, LastLineAlignment.Center, LastLineAlignment.End]) {
            final input = new LayoutInput(new TiqianTextContent(text), new TextStyle(null, 16.0),
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(true, align)), new LayoutConstraints(100),);
            final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
                WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
            final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
                WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
            TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
            if (align == LastLineAlignment.Start) {
                TracedAssertions.assertEqualsFloat(0.0, prep.gridBodyOffset);
            } else if (align == LastLineAlignment.Center) {
                TracedAssertions.assertEqualsFloatTolerance(2.0, prep.gridBodyOffset, 0.001);
            } else {
                TracedAssertions.assertEqualsFloatTolerance(4.0, prep.gridBodyOffset, 0.001);
            }
        }
    }

    @:test public static function dynamicShapingTriggersAndEmphasisItalic():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("dynamicShapingTriggersAndEmphasisItalic");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();

        final simpleInput = new LayoutInput(new TiqianTextContent("\u4E2D\u6587\u6B63\u6587\u6392\u7248"), null, null, new LayoutConstraints(500));
        final simpleAnnotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, simpleInput,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final simplePrep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, simpleInput, simpleAnnotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(simplePrep != null, simplePrep == null ? "null" : "ParagraphLayoutPrep@identity");

        final input = new LayoutInput(new TiqianTextContent("Hello World with English Words", null, null,
            [new LineBreakSpan(new TextRange(0, 11), LineBreakPolicy.ProgressiveTechnical)]),
            null, null, new LayoutConstraints(50), null, [
                new DecorationSpan(new TextRange(0, 5), DecorationKind.Emphasis),
                new DecorationSpan(new TextRange(6, 11), DecorationKind.ProperNoun),
            ],);
        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.tierMap(new TextRange(0, 11), [ProgressiveBreakTier.Structural]));
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");

        final overMeasureInput = new LayoutInput(new TiqianTextContent("VeryLongEnglishWordThatExceedsMeasure"), null, null, new LayoutConstraints(30));
        final overMeasureAnnotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, overMeasureInput,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final overMeasurePrep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, overMeasureInput, overMeasureAnnotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(overMeasurePrep != null, overMeasurePrep == null ? "null" : "ParagraphLayoutPrep@identity");
    }

    @:test public static function conflictingOpenTypeFeaturesThrows():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("conflictingOpenTypeFeaturesThrows");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine(null, new ConflictingOpenTypeFeaturesShaper());
        final input = new LayoutInput(new TiqianTextContent("\u6D4B\u8BD5"), null, null, new LayoutConstraints(300));
        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());

        final error = TracedAssertions.assertFailsWith(null,
            () -> WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
                WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers()));
        TracedAssertions.assertTrue(error.message.indexOf("Conflicting OpenType features") >= 0);
    }

    @:test public static function adjacentInlineObjectBoundariesMergingAndConflicts():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("adjacentInlineObjectBoundariesMergingAndConflicts");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "\u4E00\u4E8C\u4E09\u56DB";

        for (uniform1 in [true, false]) {
            for (uniform2 in [true, false]) {
                for (prevent1 in [true, false]) {
                    for (prevent2 in [true, false]) {
                        final obj1 = new InlineObjectSpan(new TextRange(1, 2), 20.0, 12.0, 4.0, null,
                            new InlineObjectBoundaryAdjustment(uniform1,
                                new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0, 15.0), 2.0, 1.0, prevent1));
                        final obj2 = new InlineObjectSpan(new TextRange(2, 3), 20.0, 12.0, 4.0,
                            new InlineObjectBoundaryAdjustment(uniform2,
                                new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0, 20.0), null, 0.0, prevent2),
                            null);
                        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300), null, null, null, null,
                            [obj1, obj2]);
                        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
                            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
                        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
                            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
                        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
                    }
                }
            }
        }

        final obj1 = new InlineObjectSpan(new TextRange(1, 2), 20.0, 12.0, 4.0, null,
            new InlineObjectBoundaryAdjustment(null, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0, 15.0), null,
                0.0, null));
        final conflictingObj2 = new InlineObjectSpan(new TextRange(2, 3), 20.0, 12.0, 4.0,
            new InlineObjectBoundaryAdjustment(null, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 10.0, 20.0), null, 0.0, null),
            null);
        final conflictInput = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300), null, null, null, null,
            [obj1, conflictingObj2]);
        final conflictAnnotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, conflictInput,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final conflictError = TracedAssertions.assertFailsWith(null,
            () -> WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, conflictInput, conflictAnnotation,
                WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers()));
        TracedAssertions.assertTrue(conflictError.message.indexOf("Conflicting inline-object stretch classes") >= 0);
    }

    @:test public static function verbatimRangesAndAutoSpaceDecisions():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("verbatimRangesAndAutoSpaceDecisions");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "\u4E2D\u6587 English \u6DF7\u6392\u6D4B\u8BD5 12345";
        final input = new LayoutInput(new TiqianTextContent(text, null, null, null, [new TextRange(0, 15)]), null, null, new LayoutConstraints(300), null,
            null, null, [new InlineBoxSpan(new TextRange(2, 9), null, null, InlineBoxOuterSpacing.Narrow)], null,);
        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
    }

    @:test public static function rubySpreadAccumulationAndEdges():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("rubySpreadAccumulationAndEdges");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "\u4E2D\u6587\u6D4B\u8BD5\u6BB5\u843D";
        final ruby0 = new RubySpan(new TextRange(0, 2), "zh\u014Dngw\u00E9n", null, RubyKind.Pinyin);
        final ruby1 = new RubySpan(new TextRange(2, 4), "c\u00E8sh\u00ECch\u00E1ngd\u00E0", null, RubyKind.Pinyin);
        final ruby2 = new RubySpan(new TextRange(4, 6), "du\u00E0nlu\u00F2ch\u00E1ngd\u00E0", null, RubyKind.Pinyin);
        final rubyInvalid = new RubySpan(new TextRange(99, 100), "invalid", null, RubyKind.Pinyin);

        final input = new LayoutInput(new TiqianTextContent(text, null, [1, 2, 3, 4, 5]), null, null, new LayoutConstraints(300), null, null,
            [ruby0, ruby1, ruby2, rubyInvalid],);
        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
    }

    @:test public static function shrinkOpportunitiesCoverAllPunctuationClassesAndSpaces():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("shrinkOpportunitiesCoverAllPunctuationClassesAndSpaces");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine(WidthIndependentAnnotationCacheCoverageTestSupport.nonGbResolver());
        final text = "\u300C\u5F15\u7528\u300D\u00B7\u4E2D\u70B9\u2027\u95F4\u9694\u2022\u4E2D\u70B9\uFF0C\u9017\u53F7\u3002\u53E5\u53F7\uFF01\u95EE\u53F7\uFF1F\uFF0E\u70B9\u53F7\u3001\u987F\u53F7\u4EE5\u53CA English words \u95F4\u8DDD";
        final spans = WidthIndependentAnnotationCacheCoverageTestSupport.textSpanList(text, 16.0);
        for (allowInlineStop in [true, false]) {
            for (allowSinoWestern in [true, false]) {
                final sbs:Array<Int> = [];
                for (i in 0...std.UString.count(text))
                    sbs.push(i);
                final input = new LayoutInput(new TiqianTextContent(text, spans, sbs), null, null, new LayoutConstraints(300), null, null, null, null, [
                    new InlineObjectSpan(new TextRange(0, 1), 20.0, 12.0, 4.0, null, new InlineObjectBoundaryAdjustment(null, null, 5.0, 0.0, null))
                ],);
                final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
                    WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
                final modifiedAnnotation = WidthIndependentAnnotationCacheCoverageTestSupport.withAdjustedProfile(annotation, allowInlineStop,
                    allowSinoWestern);
                final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, modifiedAnnotation,
                    WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
                TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
                TracedAssertions.assertTrue(prep.shrinkOpportunities.length > 0);
            }
        }
    }

    @:test public static function styleAtAndEmphasisItalicAtAndDynamicShapingBranches():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("styleAtAndEmphasisItalicAtAndDynamicShapingBranches");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "English \u4E2D\u6587 \u6DF7\u6392 Latin \u6D4B\u8BD5 \u6837\u5F0F";
        final spans:Array<TextSpan> = [new TextSpan(new TextRange(8, 10), new TextStyle(null, 24.0))];
        final decorations:Array<DecorationSpan> = [
            new DecorationSpan(new TextRange(0, 7), DecorationKind.Emphasis),
            new DecorationSpan(new TextRange(11, 13), DecorationKind.ProperNoun),
        ];
        final lineBreakSpans:Array<LineBreakSpan> = [new LineBreakSpan(new TextRange(0, 7), LineBreakPolicy.ProgressiveTechnical)];
        final input = new LayoutInput(new TiqianTextContent(text, spans, null, lineBreakSpans), null, null, new LayoutConstraints(50), null, decorations,);

        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertEqualsFloat(24.0, annotation.fontSizeAt(8));
        TracedAssertions.assertEqualsFloat(24.0, annotation.fontSizeAt(9));
        TracedAssertions.assertEqualsFloat(input.textStyle.fontSize, annotation.fontSizeAt(-1));
        TracedAssertions.assertEqualsFloat(input.textStyle.fontSize, annotation.fontSizeAt(0));
        TracedAssertions.assertEqualsFloat(input.textStyle.fontSize, annotation.fontSizeAt(7));
        TracedAssertions.assertEqualsFloat(input.textStyle.fontSize, annotation.fontSizeAt(10));
        TracedAssertions.assertEqualsFloat(input.textStyle.fontSize, annotation.fontSizeAt(20));
        TracedAssertions.assertEqualsFloat(input.textStyle.fontSize, annotation.fontSizeAt(100));

        final rejected = WidthIndependentAnnotationCacheCoverageTestSupport.tierMap(new TextRange(0, 7), [ProgressiveBreakTier.Structural]);
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation, rejected);
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");

        final noBreakInput = new LayoutInput(new TiqianTextContent("English"), null, null, new LayoutConstraints(500));
        final noBreakAnnotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, noBreakInput,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final prepNoDynamic = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, noBreakInput, noBreakAnnotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prepNoDynamic != null, prepNoDynamic == null ? "null" : "ParagraphLayoutPrep@identity");

        final smallMeasureInput = new LayoutInput(new TiqianTextContent("English"), null, null, new LayoutConstraints(1));
        final smallAnnotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, smallMeasureInput,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final prepSmall = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, smallMeasureInput, smallAnnotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prepSmall != null, prepSmall == null ? "null" : "ParagraphLayoutPrep@identity");

        final modifiedAnnotation = WidthIndependentAnnotationCacheCoverageTestSupport.withFirstFontDecisionOnly(annotation);
        final prepUnknownRoles = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, modifiedAnnotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prepUnknownRoles != null, prepUnknownRoles == null ? "null" : "ParagraphLayoutPrep@identity");
    }

    @:test public static function rubySpreadSecondVisitAndZeroFirstCluster():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("rubySpreadSecondVisitAndZeroFirstCluster");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u4E03\u516B";
        final ruby0a = new RubySpan(new TextRange(0, 1), "ch\u00E1ngd\u00E0ch\u00E1ngd\u00E0", null, RubyKind.Pinyin);
        final ruby0b = new RubySpan(new TextRange(0, 1), "ch\u00E1ngd\u00E0ch\u00E1ngd\u00E0", null, RubyKind.Pinyin);
        final ruby1 = new RubySpan(new TextRange(2, 3), "ch\u00E1ngd\u00E0ch\u00E1ngd\u00E0ch\u00E1ngd\u00E0", null, RubyKind.Pinyin);
        final ruby2 = new RubySpan(new TextRange(2, 3), "ch\u00E1ngd\u00E0ch\u00E1ngd\u00E0ch\u00E1ngd\u00E0", null, RubyKind.Pinyin);

        final sbs:Array<Int> = [];
        for (i in 0...std.UString.count(text))
            sbs.push(i);
        final input = new LayoutInput(new TiqianTextContent(text, null, sbs), null, null, new LayoutConstraints(300), null, null,
            [ruby0a, ruby0b, ruby1, ruby2],);
        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
    }

    @:test public static function pairedPunctuationWithZeroCapacity():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("pairedPunctuationWithZeroCapacity");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "\uFF08\u62EC\u53F7\uFF09";
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300));
        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, annotation,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
    }

    @:test public static function dynamicShapingEmphasisItalicAtAndZeroPairedCapacityBranches():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("dynamicShapingEmphasisItalicAtAndZeroPairedCapacityBranches");
        final engine = WidthIndependentAnnotationCacheCoverageTestSupport.engine();
        final text = "Hello World Latin";
        final input = new LayoutInput(new TiqianTextContent(text, null, null,
            [new LineBreakSpan(new TextRange(0, 17), LineBreakPolicy.ProgressiveTechnical)]), null, null,
            new LayoutConstraints(100), null, [
                new DecorationSpan(new TextRange(0, 5), DecorationKind.ProperNoun),
                new DecorationSpan(new TextRange(6, 11), DecorationKind.Emphasis),
            ],);
        final annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine, input,
            WidthIndependentAnnotationCacheCoverageTestSupport.emptyTiers());
        final uncachedAnnotation = WidthIndependentAnnotationCacheCoverageTestSupport.withEmptyShapingCache(annotation);

        final rejected = WidthIndependentAnnotationCacheCoverageTestSupport.tierMap(new TextRange(0, 17), [ProgressiveBreakTier.Structural]);
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(engine, input, uncachedAnnotation, rejected);
        TracedAssertions.assertNotNullRendered(prep != null, prep == null ? "null" : "ParagraphLayoutPrep@identity");
    }

    @:test public static function centeredPunctBeforeAttachedReferenceKeepsLeadingGlueOnly():Void {
        final t = new TestTraceRecorder("WidthIndependentAnnotationCacheCoverageTest");
        t.section("centeredPunctBeforeAttachedReferenceKeepsLeadingGlueOnly");
        final text = "\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u00B7[1]\uFF0C\u540E\u6587";
        final attachAt = WidthIndependentAnnotationCacheCoverageTestSupport.indexOf(text, "[1]");
        final result = WidthIndependentAnnotationCacheCoverageTestSupport.engine(null, new NarrowInkShaper())
            .layout(new LayoutInput(new TiqianTextContent(text, [
                new TextSpan(new TextRange(attachAt, attachAt + 3), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
            ],), null, new ParagraphStyle(null, null, null, Ic.Zero),
                new LayoutConstraints(320),),);
        var boundary:org.tiqian.core.SpacingDecisionInfo = null;
        for (i in 0...result.debug.spacingDecisions.length) {
            final d = result.debug.spacingDecisions[i];
            if (d.reason.indexOf("AttachedInlineVirtualPunctuationBoundary") == 0) {
                boundary = d;
                break;
            }
        }
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:adjacent-punctuation", boundary.reason);
        TracedAssertions.assertEqualsString("\u00B7", boundary.leftChar);
        TracedAssertions.assertEqualsString("\uFF0C", boundary.rightChar);
        TracedAssertions.assertTrue(boundary.naturalInnerGlue > 0.0);
        TracedAssertions.assertTrue(boundary.reduction > 0.0);
        TracedAssertions.assertEqualsInt(WidthIndependentAnnotationCacheCoverageTestSupport.indexOf(text, "\u00B7"), boundary.reductionTargetRange.start);
    }
}
