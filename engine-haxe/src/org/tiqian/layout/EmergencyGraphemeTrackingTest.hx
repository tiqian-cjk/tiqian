package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.EmergencyGraphemeTrackingTestSupport;
import org.tiqian.linebreak.EnglishHyphenation;

class EmergencyGraphemeTrackingTest {
    @:test public static function hashPieceInsideTechnicalUrlSkipsSyllableClassification():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("hashPieceInsideTechnicalUrlSkipsSyllableClassification");
        final hash = "deadbeefcafebabefeedfaceabcdefabcdef";
        final text = "https://example.com/commit/" + hash;
        final hashStart = text.indexOf(hash);
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 192, [new LineBreakSpan(new TextRange(0, text.length), ProgressiveTechnical)]);
        final syllableOffsets = EmergencyGraphemeTrackingTestSupport.breakOffsetsForTier(result.debug.breakOpportunityDecisions, "Syllable");
        var none = true;
        for (i in 0...syllableOffsets.length) {
            if (syllableOffsets[i] > hashStart && syllableOffsets[i] < text.length) {
                none = false;
                break;
            }
        }
        TracedAssertions.assertTrue(none, EmergencyGraphemeTrackingTestSupport.renderInts(syllableOffsets));
        var allZero = true;
        for (i in 0...result.lines.length) {
            if (result.lines[i].hyphenAdvance != 0) {
                allZero = false;
                break;
            }
        }
        TracedAssertions.assertTrue(allZero);
    }

    @:test public static function longAllCapsWesternWordDoesNotBecomeTrackingEligible():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("longAllCapsWesternWordDoesNotBecomeTrackingEligible");
        final text = "SUPERCALIFRAGILISTICEXPIALIDOCIOUS";
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 101);
        TracedAssertions.assertTrue(result.debug.emergencyTrackingEligibilityDecisions.length == 0);
        final trackAllocs = EmergencyGraphemeTrackingTestSupport.allocationsForKind(result.debug.justificationDecisions, "EmergencyGraphemeTracking");
        TracedAssertions.assertFalse(trackAllocs.length > 0);
    }

    @:test public static function ordinaryWesternProseIsNeverInferredAsTrackingEligible():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("ordinaryWesternProseIsNeverInferredAsTrackingEligible");
        final text = "ordinary Western paragraphs keep their natural word spacing";
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 137);
        TracedAssertions.assertTrue(result.debug.emergencyTrackingEligibilityDecisions.length == 0);
        final trackAllocs = EmergencyGraphemeTrackingTestSupport.allocationsForKind(result.debug.justificationDecisions, "EmergencyGraphemeTracking");
        TracedAssertions.assertFalse(trackAllocs.length > 0);
        var anyDeficit = false;
        for (i in 0...result.debug.justificationDecisions.length) {
            if (result.debug.justificationDecisions[i].deficitAfter > 0) {
                anyDeficit = true;
                break;
            }
        }
        TracedAssertions.assertTrue(anyDeficit, "ordinary Western lines may remain ragged after bounded word-space adjustment");
    }

    @:test public static function plainOpaqueHardBreakKeepsCombiningGraphemeIntact():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("plainOpaqueHardBreakKeepsCombiningGraphemeIntact");
        final prefix = "abc123e";
        final combiningMark = "\u0301";
        final text = prefix + combiningMark + "def456ghi";
        final combiningMarkOffset = prefix.length;
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 64);
        TracedAssertions.assertTrue(result.clusters.length > 1, EmergencyGraphemeTrackingTestSupport.renderClusters(result.clusters));
        var none = true;
        final ranges:Array<TextRange> = [];
        for (i in 0...result.clusters.length) {
            final r = result.clusters[i].range;
            ranges.push(r);
            if (r.start == combiningMarkOffset || r.end == combiningMarkOffset) {
                none = false;
            }
        }
        TracedAssertions.assertTrue(none, EmergencyGraphemeTrackingTestSupport.joinTextRanges(ranges));
    }

    @:test public static function rejectedLetterDigitStructuralOffsetsRemainAvailableAsEmergencyCuts():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("rejectedLetterDigitStructuralOffsetsRemainAvailableAsEmergencyCuts");
        final text = "Machine2Machine";
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 120, [new LineBreakSpan(new TextRange(0, text.length), ProgressiveTechnical)]);
        final emergency = EmergencyGraphemeTrackingTestSupport.breakOffsetsForTier(result.debug.breakOpportunityDecisions, "Emergency");
        var has7 = false;
        var has8 = false;
        for (i in 0...emergency.length) {
            if (emergency[i] == 7)
                has7 = true;
            if (emergency[i] == 8)
                has8 = true;
        }
        TracedAssertions.assertTrue(has7, EmergencyGraphemeTrackingTestSupport.renderInts(emergency));
        TracedAssertions.assertTrue(has8, EmergencyGraphemeTrackingTestSupport.renderInts(emergency));
        var allZero = true;
        for (i in 0...result.lines.length) {
            if (result.lines[i].hyphenAdvance != 0) {
                allZero = false;
                break;
            }
        }
        TracedAssertions.assertTrue(allZero);
    }

    @:test public static function repeatedPlainTokenGetsNarrowNonLexicalAuthorization():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("repeatedPlainTokenGetsNarrowNonLexicalAuthorization");
        final text = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 101);
        var any = false;
        for (i in 0...result.debug.emergencyTrackingEligibilityDecisions.length) {
            final d = result.debug.emergencyTrackingEligibilityDecisions[i];
            if (d.range.start == 0 && d.range.end == text.length && d.reason == "LongRepeatedLetterRun") {
                any = true;
                break;
            }
        }
        TracedAssertions.assertTrue(any);
        for (i in 0...result.lines.length) {
            if (result.lines[i].endReason == AutoWrap) {
                TracedAssertions.assertEqualsFloatTolerance(101, result.lines[i].visualWidth, 0.001);
            }
        }
    }

    @:test public static function standaloneTechnicalHashUsesTrackingToFillEveryAutoWrappedLine():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("standaloneTechnicalHashUsesTrackingToFillEveryAutoWrappedLine");
        final text = "deadbeefcafebabefeedfaceabcdefabcdef";
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 101, [new LineBreakSpan(new TextRange(0, text.length), ProgressiveTechnical)]);
        var autoCount = 0;
        for (i in 0...result.lines.length) {
            if (result.lines[i].endReason == AutoWrap)
                autoCount++;
        }
        TracedAssertions.assertTrue(autoCount > 0);
        for (i in 0...result.lines.length) {
            if (result.lines[i].endReason == AutoWrap) {
                TracedAssertions.assertEqualsFloatTolerance(101, result.lines[i].visualWidth, 0.001);
            }
        }
        var found = false;
        final allocs = EmergencyGraphemeTrackingTestSupport.allocationsForKind(result.debug.justificationDecisions, "EmergencyGraphemeTracking");
        for (i in 0...allocs.length) {
            if (allocs[i].reason == "TerminalTechnicalEmergencyTracking:ProgressiveTechnicalSpan") {
                found = true;
                break;
            }
        }
        TracedAssertions.assertTrue(found);
    }

    @:test public static function technicalIdentifierRelabelsLooseLetterDigitBoundaryAsEmergency():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("technicalIdentifierRelabelsLooseLetterDigitBoundaryAsEmergency");
        final text = "Machine2Machine";
        final result = EmergencyGraphemeTrackingTestSupport.layoutWithShaper(text, 85, new UniformAdvanceShaper(),
            [new LineBreakSpan(new TextRange(0, text.length), ProgressiveTechnical)]);
        EmergencyGraphemeTrackingTestSupport.assertEqualsTextRange(new TextRange(0, 8), result.lines[0].range);
        var foundNote = false;
        final notes = result.debug.lineDecisions[0].notes;
        for (i in 0...notes.length) {
            if (notes[i].indexOf("technical-break:Emergency") >= 0) {
                foundNote = true;
                break;
            }
        }
        TracedAssertions.assertTrue(foundNote);
        TracedAssertions.assertEqualsFloat(0.0, result.lines[0].hyphenAdvance);
    }

    @:test public static function technicalTrackingDoesNotOpenEdgesTouchingInlineObjectsOrZeroWidthControls():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("technicalTrackingDoesNotOpenEdgesTouchingInlineObjectsOrZeroWidthControls");
        final objectAs = "aaaaaaaaaaaa";
        final objectBs = "bbbbbbbbbbbb";
        final objectText = objectAs + "\uFFFC" + objectBs;
        final objectRange = new TextRange(objectAs.length, objectAs.length + 1);
        final objectLen = objectAs.length + 1 + objectBs.length;
        final objectResult = EmergencyGraphemeTrackingTestSupport.layoutWithObjects(objectText, 300, [new InlineObjectSpan(objectRange, 16, 12, 4)],
            [new LineBreakSpan(new TextRange(0, objectLen), ProgressiveTechnical)]);
        final objectAllocations = EmergencyGraphemeTrackingTestSupport.allocationsForKind(objectResult.debug.justificationDecisions,
            "EmergencyGraphemeTracking");
        TracedAssertions.assertTrue(objectAllocations.length > 0);
        var none = true;
        for (i in 0...objectAllocations.length) {
            final cr = objectAllocations[i].clusterRange;
            if (cr.end == objectRange.start || (cr.start == objectRange.start && cr.end == objectRange.end)) {
                none = false;
            }
        }
        TracedAssertions.assertTrue(none, EmergencyGraphemeTrackingTestSupport.renderAllocations(objectAllocations));

        final zeroWidthAs = "aaaaaaaaaaaa";
        final zeroWidthBs = "bbbbbbbbbbbb";
        final zeroWidthText = zeroWidthAs + "\u200B" + zeroWidthBs;
        final zeroWidthRange = new TextRange(zeroWidthAs.length, zeroWidthAs.length + 1);
        final zeroWidthLen = zeroWidthAs.length + 1 + zeroWidthBs.length;
        final zeroWidthResult = EmergencyGraphemeTrackingTestSupport.layoutWithObjects(zeroWidthText, 300, [],
            [new LineBreakSpan(new TextRange(0, zeroWidthLen), ProgressiveTechnical)]);
        final zeroWidthAllocations = EmergencyGraphemeTrackingTestSupport.allocationsForKind(zeroWidthResult.debug.justificationDecisions,
            "EmergencyGraphemeTracking");
        TracedAssertions.assertTrue(zeroWidthAllocations.length > 0);
        var noneZ = true;
        for (i in 0...zeroWidthAllocations.length) {
            final cr = zeroWidthAllocations[i].clusterRange;
            if (cr.end == zeroWidthRange.start || (cr.start == zeroWidthRange.start && cr.end == zeroWidthRange.end)) {
                noneZ = false;
            }
        }
        TracedAssertions.assertTrue(noneZ, EmergencyGraphemeTrackingTestSupport.renderAllocations(zeroWidthAllocations));
    }

    @:test public static function unannotatedUrlDoesNotAuthorizeTrackingAcrossOrdinaryPathComponents():Void {
        final t = new TestTraceRecorder("EmergencyGraphemeTrackingTest");
        t.section("unannotatedUrlDoesNotAuthorizeTrackingAcrossOrdinaryPathComponents");
        final identity = "abc123def456ghi789";
        final text = "https://example.com/path/to/" + identity;
        final identityStart = text.indexOf(identity);
        final result = EmergencyGraphemeTrackingTestSupport.layout(text, 160);
        final actualRanges:Array<TextRange> = [];
        for (i in 0...result.debug.emergencyTrackingEligibilityDecisions.length) {
            actualRanges.push(result.debug.emergencyTrackingEligibilityDecisions[i].range);
        }
        TracedAssertions.assertEqualsTextRangeArray([new TextRange(identityStart, text.length)], actualRanges);
        final trackAllocations = EmergencyGraphemeTrackingTestSupport.allocationsForKind(result.debug.justificationDecisions, "EmergencyGraphemeTracking");
        var allGte = true;
        for (i in 0...trackAllocations.length) {
            if (trackAllocations[i].clusterRange.start < identityStart) {
                allGte = false;
                break;
            }
        }
        TracedAssertions.assertTrue(allGte);
    }
}
