import org.tiqian.layout.RecordedEvidenceGoldenParityTest;
import org.tiqian.layout.QuoteClassificationEngineTest;
import org.tiqian.layout.LineGeometryDirectTailTest;
import org.tiqian.layout.PunctuationGeometryLedgerCoverageTest;
import org.tiqian.layout.PunctuationSpacingRuleTest;
import org.tiqian.layout.PunctuationGeometryBranchArmsCoverageTest;
import org.tiqian.layout.UnicodeEmoji17RgiRoleAuditTest;
import org.tiqian.layout.OpeningBracketLineStartTest;
import org.tiqian.layout.VerbatimRangeAutoSpaceTest;
import org.tiqian.layout.ZeroWidthBreakControlLayoutTest;
import org.tiqian.layout.PunctuationBodyFloorInvariantTest;
import org.tiqian.layout.BaselineAlignmentTest;
import org.tiqian.layout.InterpunctShrinkOpportunityTest;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.CoreUnitsGeometryTest;
import org.tiqian.core.CoreLayoutQueriesGapsTest;
import org.tiqian.core.LayoutQueriesTest;
import org.tiqian.core.LayoutQueriesResidualCoverageTest;
import org.tiqian.core.CoreBoundaryTest;
import org.tiqian.core.LinkAddressDisplayTest;
import org.tiqian.core.SourceInteractionBoundariesCoverageTest;
import org.tiqian.core.TextModelCoverageTest;
import org.tiqian.core.EastAsianSpacingTest;
import org.tiqian.core.EastAsianSpacingCoverageTest;
import org.tiqian.core.EastAsianSpacingLookupCoverageTest;
import org.tiqian.core.TextRangeTest;
import org.tiqian.core.UnicodeNumberTest;
import org.tiqian.core.UnicodeScriptEvidenceTest;
import org.tiqian.core.UnicodeWordCharacterTest;
import org.tiqian.clreq.BopomofoParserTest;
import org.tiqian.clreq.NumberSymbolCohesionTest;
import org.tiqian.clreq.KinsokuLevelTest;
import org.tiqian.clreq.PunctuationGluePlacementTest;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutorTest;
import org.tiqian.clreq.ClreqProfileCoverageTest;
import org.tiqian.clreq.ClreqPolicyTailCoverageTest;
import org.tiqian.font.CjkDashCapabilityPolicyTest;
import org.tiqian.font.CjkFontRoleClassifierTest;
import org.tiqian.font.FontPolicyCoverageTest;
import org.tiqian.font.FontRoleTailCoverageTest;
import org.tiqian.font.InlineShapingStylePolicyTest;
import org.tiqian.font.ScriptAwareFontMetricsNormalizerTest;
import org.tiqian.font.UsesLatinFaceTest;
import org.tiqian.shaping.TextShaperCoverageTest;
import org.tiqian.layout.ParagraphShapingStageCoverageTest;
import org.tiqian.shaping.ExplainableStubTextShaperTest;
import org.tiqian.shaping.ReplayableFontBackendCoverageTest;
import org.tiqian.linebreak.EnglishHyphenationTest;
import org.tiqian.linebreak.LiangHyphenatorTest;
import org.tiqian.layout.ProgressiveBreakDecisionsCoverageTest;
import org.tiqian.layout.ProgressiveBreakDecisionsTailTest;
import org.tiqian.layout.DecideHyphenBreakTest;
import org.tiqian.layout.QuotePairAnalyzerTest;
import org.tiqian.layout.QuotePairAnalyzerCoverageTest;
import org.tiqian.layout.QuotePairAnalyzerSurrogateAdjacencyTest;
import org.tiqian.layout.PunctuationModelCoverageTest;
import org.tiqian.layout.PunctuationAtomBuilderHaltTest;
import org.tiqian.layout.LineOptimizationCoverageTest;
import org.tiqian.layout.ContextualDashEllipsisRoleResolverCoverageTest;
import org.tiqian.layout.ContextualDashEllipsisRoleResolverTest;
import org.tiqian.layout.ContextualDashEllipsisClusterCoverageTest;
import org.tiqian.layout.ContextualRoleExtensionCoverageTest;
import org.tiqian.layout.ContextualQuoteRoleResolverCoverageTest;
import org.tiqian.layout.ContextualQuoteRoleResolverNestedAndSurrogateTest;
import org.tiqian.layout.ClusterRoleResolutionCoverageTest;
import org.tiqian.layout.ClusterRoleResolutionSurrogateAndExtenderEdgeTest;
import org.tiqian.layout.LineRepairTailCoverageTest;
import org.tiqian.layout.LineRepairCoverageTest;
import org.tiqian.layout.JustifierTest;
import org.tiqian.layout.JustifierCoverageTest;
import org.tiqian.layout.JustifierCompressionTest;
import org.tiqian.layout.JustifierJfTest;
import org.tiqian.layout.UnicodePunctuationBoundaryResolverCoverageTest;
import org.tiqian.layout.PunctuationGeometryStageCoverageTest;
import org.tiqian.layout.PreparedParagraphJsonNumberTest;
import org.tiqian.layout.PreparedParagraphJfTest;
import org.tiqian.layout.PreparedParagraphPlanConstructionTest;
import org.tiqian.layout.PreparedParagraphInlineEdgesTest;
import org.tiqian.layout.ParagraphDpLineBreakerTest;
import org.tiqian.layout.ParagraphDpLineBreakerCoverageTest;
import org.tiqian.layout.ParagraphDpLineBreakerCoverage2Test;
import org.tiqian.layout.GreedyLineBreakerTest;
import org.tiqian.layout.LookaheadLineBreakerTest;
import org.tiqian.layout.LineBreakerCoverage2Test;
import org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest;
import org.tiqian.linebreak.LineBreakCoverageTest;
import org.tiqian.linebreak.MandatoryBreakTest;
import org.tiqian.linebreak.UnicodePunctuationLineBreakCoverageTest;
import org.tiqian.linebreak.UnicodePunctuationLineBreakTest;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TraceAssertionException;
import std.Console;
import org.tiqian.layout.ExplainableStubParagraphLayoutEngineTest;
import org.tiqian.layout.JustifierEngineTest;
import std.Process;

class Main {
    private static var failures:Int = 0;

    private static function run(name:String, test:() -> Void):Void {
        try {
            test();
        } catch (error:TraceAssertionException) {
            failures += 1;
            Console.log("FAIL " + name + ": " + error.message);
        } catch (error:TiqianIllegalArgumentException) {
            failures += 1;
            Console.log("FAIL " + name + ": " + error.message);
        }
    }

    public static function main():Void {
        StringBufOracle.install();
        SortedTablesOracle.install();
        FunctionalOracle.install();
        js.Syntax.code("globalThis.std = globalThis.std || {}; globalThis.std.UStringPlatform = {0};", UStringPlatform);
        js.Syntax.code("std_ReadOnlyArray.iterator = function(a) { return new haxe_iterators_ArrayIterator(a); };");
        UStringRTOracle.install();
        run("hyphenatesCommonWordsAtSyllablePoints", EnglishHyphenationTest.hyphenatesCommonWordsAtSyllablePoints);
        run("respectsMarginsAndShortWords", EnglishHyphenationTest.respectsMarginsAndShortWords);
        run("honoursTheExceptionList", EnglishHyphenationTest.honoursTheExceptionList);
        run("noHyphenatorYieldsNoOpportunities", LiangHyphenatorTest.noHyphenatorYieldsNoOpportunities);
        run("oddLevelGapBecomesABreakOutsideTheMargins", LiangHyphenatorTest.oddLevelGapBecomesABreakOutsideTheMargins);
        run("maxLevelWinsAndEvenForbidsTheBreak", LiangHyphenatorTest.maxLevelWinsAndEvenForbidsTheBreak);
        run("marginsAndShortWordsAreRespected", LiangHyphenatorTest.marginsAndShortWordsAreRespected);
        run("exceptionsOverridePatternsAndAreCaseInsensitive", LiangHyphenatorTest.exceptionsOverridePatternsAndAreCaseInsensitive);
        run("parsesPatternsAndExceptionBlocksStrippingComments", LiangHyphenatorTest.parsesPatternsAndExceptionBlocksStrippingComments);
        run("matchesDoubleQuotePair", QuotePairAnalyzerTest.matchesDoubleQuotePair);
        run("matchesSingleQuotePair", QuotePairAnalyzerTest.matchesSingleQuotePair);
        run("matchesNestedQuotePairs", QuotePairAnalyzerTest.matchesNestedQuotePairs);
        run("unmatchedQuotesProduceNoPairs", QuotePairAnalyzerTest.unmatchedQuotesProduceNoPairs);
        run("contractionApostropheDoesNotCloseOuterSingleQuote", QuotePairAnalyzerTest.contractionApostropheDoesNotCloseOuterSingleQuote);
        run("contractionInsideCjkSingleQuotesKeepsApostropheLatin", QuotePairAnalyzerTest.contractionInsideCjkSingleQuotesKeepsApostropheLatin);
        run("inWordApostropheMatrixDoesNotConsumeOuterQuotePairs", QuotePairAnalyzerTest.inWordApostropheMatrixDoesNotConsumeOuterQuotePairs);
        run("unmatchedCurlyQuotesUseDirectionalContext", QuotePairAnalyzerTest.unmatchedCurlyQuotesUseDirectionalContext);
        run("mismatchedNestingLeavesQuotesUnmatched", QuotePairAnalyzerTest.mismatchedNestingLeavesQuotesUnmatched);
        run("classifiesPairAsCjkWhenOuterContextIsCjk", QuotePairAnalyzerTest.classifiesPairAsCjkWhenOuterContextIsCjk);
        run("classifiesPairAsLatinWhenOuterContextIsLatin", QuotePairAnalyzerTest.classifiesPairAsLatinWhenOuterContextIsLatin);
        run("classifiesBothQuotesAsCjkForCjkQuotedLatinContent", QuotePairAnalyzerTest.classifiesBothQuotesAsCjkForCjkQuotedLatinContent);
        run("whitespaceDelimitedLatinQuotePairOverridesCjkOuterContext", QuotePairAnalyzerTest.whitespaceDelimitedLatinQuotePairOverridesCjkOuterContext);
        run("unspacedCjkQuotationOfLatinTextRemainsCjk", QuotePairAnalyzerTest.unspacedCjkQuotationOfLatinTextRemainsCjk);
        run("adjacentQuotedListItemsDoNotUsePreviousItemContentAsOuterContext",
            QuotePairAnalyzerTest.adjacentQuotedListItemsDoNotUsePreviousItemContentAsOuterContext);
        run("spacedCjkQuotedContentRemainsCjk", QuotePairAnalyzerTest.spacedCjkQuotedContentRemainsCjk);
        run("classifiesPairAsCjkAtTextBoundary", QuotePairAnalyzerTest.classifiesPairAsCjkAtTextBoundary);
        run("classifiesTextStartLatinPairFromQuotedContent", QuotePairAnalyzerTest.classifiesTextStartLatinPairFromQuotedContent);
        run("mixedChineseQuestionAtParagraphStartUsesParagraphLanguage", QuotePairAnalyzerTest.mixedChineseQuestionAtParagraphStartUsesParagraphLanguage);
        run("explicitEnglishParagraphLanguageWinsForMixedQuotation", QuotePairAnalyzerTest.explicitEnglishParagraphLanguageWinsForMixedQuotation);
        run("commonDigitsDoNotChooseTheQuoteRole", QuotePairAnalyzerTest.commonDigitsDoNotChooseTheQuoteRole);
        run("nonLatinWesternScriptsParticipateAsStrongScriptEvidence", QuotePairAnalyzerTest.nonLatinWesternScriptsParticipateAsStrongScriptEvidence);
        run("numberedCjkQuotePrefixUsesQuotedContent", QuotePairAnalyzerTest.numberedCjkQuotePrefixUsesQuotedContent);
        run("numberedLatinQuotePrefixStillUsesLatinContent", QuotePairAnalyzerTest.numberedLatinQuotePrefixStillUsesLatinContent);
        run("classifiesNestedPairsByOutermostContext", QuotePairAnalyzerTest.classifiesNestedPairsByOutermostContext);
        run("classifiesLatinNestedQuotesByOuterContext", QuotePairAnalyzerTest.classifiesLatinNestedQuotesByOuterContext);
        run("skipsAsciiPunctuationWhenResolvingContext", QuotePairAnalyzerTest.skipsAsciiPunctuationWhenResolvingContext);
        run("skipsNeutralDashWhenResolvingContext", QuotePairAnalyzerTest.skipsNeutralDashWhenResolvingContext);
        run("endOfTextQuotePairClassifiedByOuterContext", QuotePairAnalyzerTest.endOfTextQuotePairClassifiedByOuterContext);
        run("representativeQuoteContextMatrixRemainsStable", QuotePairAnalyzerTest.representativeQuoteContextMatrixRemainsStable);
        run("roleDecisionSourcesStayExplainableAcrossFallbackPaths", QuotePairAnalyzerTest.roleDecisionSourcesStayExplainableAcrossFallbackPaths);
        TestTraceRecorder.flushClass("QuotePairAnalyzerTest");
        run("deprecatedClassifyPairsWithFontRoleClassifierDelegates", QuotePairAnalyzerCoverageTest.deprecatedClassifyPairsWithFontRoleClassifierDelegates);
        run("deprecatedClassifyQuoteRolesWithFontRoleClassifierDelegates",
            QuotePairAnalyzerCoverageTest.deprecatedClassifyQuoteRolesWithFontRoleClassifierDelegates);
        run("codePointBeforeSurrogatePairReturnsSupplementary", QuotePairAnalyzerCoverageTest.codePointBeforeSurrogatePairReturnsSupplementary);
        run("codePointAtOrNullSurrogatePairReturnsSupplementary", QuotePairAnalyzerCoverageTest.codePointAtOrNullSurrogatePairReturnsSupplementary);
        run("codePointAtOrNullNonSurrogateReturnsSelf", QuotePairAnalyzerCoverageTest.codePointAtOrNullNonSurrogateReturnsSelf);
        run("codePointBeforeReturnsNullAtStart", QuotePairAnalyzerCoverageTest.codePointBeforeReturnsNullAtStart);
        run("codePointBeforeReturnsSupplementaryForSurrogatePair", QuotePairAnalyzerCoverageTest.codePointBeforeReturnsSupplementaryForSurrogatePair);
        run("quotePairAwareFontRoleClassifierUsesOverride", QuotePairAnalyzerCoverageTest.quotePairAwareFontRoleClassifierUsesOverride);
        run("quotePairAwareFontRoleClassifierDelegatesWhenNoOverride", QuotePairAnalyzerCoverageTest.quotePairAwareFontRoleClassifierDelegatesWhenNoOverride);
        run("doubleQuoteCloseWithEmptyStackIgnores", QuotePairAnalyzerCoverageTest.doubleQuoteCloseWithEmptyStackIgnores);
        run("singleQuoteCloseWithEmptyStackIgnores", QuotePairAnalyzerCoverageTest.singleQuoteCloseWithEmptyStackIgnores);
        run("inWordApostropheAfterSupplementaryDoesNotClose", QuotePairAnalyzerCoverageTest.inWordApostropheAfterSupplementaryDoesNotClose);
        run("codePointAtOrNullWithSupplementaryAfterQuote", QuotePairAnalyzerCoverageTest.codePointAtOrNullWithSupplementaryAfterQuote);
        run("codePointBeforeWithHighSurrogateBeforeQuote", QuotePairAnalyzerCoverageTest.codePointBeforeWithHighSurrogateBeforeQuote);
        run("codePointBeforeWithLowSurrogateAtStart", QuotePairAnalyzerCoverageTest.codePointBeforeWithLowSurrogateAtStart);
        run("codePointBeforeWithLowSurrogateAfterNonHighSurrogate", QuotePairAnalyzerCoverageTest.codePointBeforeWithLowSurrogateAfterNonHighSurrogate);
        run("codePointAtOrNullWithIndexOutOfRange", QuotePairAnalyzerCoverageTest.codePointAtOrNullWithIndexOutOfRange);
        run("codePointAtOrNullWithHighSurrogateAtEnd", QuotePairAnalyzerCoverageTest.codePointAtOrNullWithHighSurrogateAtEnd);
        run("codePointAtOrNullWithHighSurrogateFollowedByNonLowSurrogate",
            QuotePairAnalyzerCoverageTest.codePointAtOrNullWithHighSurrogateFollowedByNonLowSurrogate);
        run("analyzeWithDoubleQuoteOpen", QuotePairAnalyzerCoverageTest.analyzeWithDoubleQuoteOpen);
        run("codePointAtOrNullHighSurrogateNotInRangeReturnsHigh", QuotePairAnalyzerCoverageTest.codePointAtOrNullHighSurrogateNotInRangeReturnsHigh);
        run("codePointBeforeLowInRangeIndexGe2HighNotInRange", QuotePairAnalyzerCoverageTest.codePointBeforeLowInRangeIndexGe2HighNotInRange);
        run("singleQuotePairMatch", QuotePairAnalyzerCoverageTest.singleQuotePairMatch);
        run("codePointAtOrNullLoneHighSurrogateAfterQuote", QuotePairAnalyzerCoverageTest.codePointAtOrNullLoneHighSurrogateAfterQuote);
        run("codePointAtOrNullHighSurrogateAtStringEnd", QuotePairAnalyzerCoverageTest.codePointAtOrNullHighSurrogateAtStringEnd);
        run("analyzeWithAllQuoteTypes", QuotePairAnalyzerCoverageTest.analyzeWithAllQuoteTypes);
        run("codePointBeforeNonSurrogateBmpChar", QuotePairAnalyzerCoverageTest.codePointBeforeNonSurrogateBmpChar);
        TestTraceRecorder.flushClass("QuotePairAnalyzerCoverageTest");
        run("lowQuoteCodePointsTakeTheSwitchDefaultWithoutPairing",
            QuotePairAnalyzerSurrogateAdjacencyTest.lowQuoteCodePointsTakeTheSwitchDefaultWithoutPairing);
        run("apostropheAfterASurrogatePairWalksTheCombineArmBefore",
            QuotePairAnalyzerSurrogateAdjacencyTest.apostropheAfterASurrogatePairWalksTheCombineArmBefore);
        run("apostropheBeforeASurrogateWalksBothLowCheckArms", QuotePairAnalyzerSurrogateAdjacencyTest.apostropheBeforeASurrogateWalksBothLowCheckArms);
        run("plainAndBoundaryNeighboursWalkTheNonSurrogateArms", QuotePairAnalyzerSurrogateAdjacencyTest.plainAndBoundaryNeighboursWalkTheNonSurrogateArms);
        TestTraceRecorder.flushClass("QuotePairAnalyzerSurrogateAdjacencyTest");
        TestTraceRecorder.flushClass("EnglishHyphenationTest");
        TestTraceRecorder.flushClass("LiangHyphenatorTest");
        run("defaultsAdmitTheCleanTierWithoutGeometryInputs", ProgressiveBreakDecisionsCoverageTest.defaultsAdmitTheCleanTierWithoutGeometryInputs);
        run("lineStartAtTheOverflowBoundaryScansAnEmptyRange", ProgressiveBreakDecisionsCoverageTest.lineStartAtTheOverflowBoundaryScansAnEmptyRange);
        run("twoSameTierBoundariesPickTheRightmost", ProgressiveBreakDecisionsCoverageTest.twoSameTierBoundariesPickTheRightmost);
        run("visiblyLooseCleanTiersFallThroughToEmergency", ProgressiveBreakDecisionsCoverageTest.visiblyLooseCleanTiersFallThroughToEmergency);
        run("aLeftwardEmergencyBoundaryKeepsTheBestCleanTier", ProgressiveBreakDecisionsCoverageTest.aLeftwardEmergencyBoundaryKeepsTheBestCleanTier);
        run("spanEdgeAndWhitespaceClustersDoNotCountAsTechnicalUnits",
            ProgressiveBreakDecisionsCoverageTest.spanEdgeAndWhitespaceClustersDoNotCountAsTechnicalUnits);
        run("singleTechnicalUnitFallsBackToTheCjkGapDensity", ProgressiveBreakDecisionsCoverageTest.singleTechnicalUnitFallsBackToTheCjkGapDensity);
        run("candidateOutsideTheClusterListIsAllowed", ProgressiveBreakDecisionsCoverageTest.candidateOutsideTheClusterListIsAllowed);
        run("candidatesOutsideTheActiveSpanAreAllowed", ProgressiveBreakDecisionsCoverageTest.candidatesOutsideTheActiveSpanAreAllowed);
        run("candidatesOfADifferentSpanAreAllowed", ProgressiveBreakDecisionsCoverageTest.candidatesOfADifferentSpanAreAllowed);
        run("sameTierPastTheRawGreedyIsAllowedAndWorseTiersAreNot", ProgressiveBreakDecisionsCoverageTest.sameTierPastTheRawGreedyIsAllowedAndWorseTiersAreNot);
        run("candidatesBeforeTheRawGreedyMustMatchTheSelectedBoundary",
            ProgressiveBreakDecisionsCoverageTest.candidatesBeforeTheRawGreedyMustMatchTheSelectedBoundary);
        run("hyphenBreakReturnsOverflowAtPlainWordBoundaries", ProgressiveBreakDecisionsCoverageTest.hyphenBreakReturnsOverflowAtPlainWordBoundaries);
        run("overLongWordsMustHyphenateFromTheLineStart", ProgressiveBreakDecisionsCoverageTest.overLongWordsMustHyphenateFromTheLineStart);
        run("aFittingWholeWordBreaksThere", ProgressiveBreakDecisionsCoverageTest.aFittingWholeWordBreaksThere);
        run("sinoWesternGapsAbsorbingTheDeficitKeepTheWholeWord", ProgressiveBreakDecisionsCoverageTest.sinoWesternGapsAbsorbingTheDeficitKeepTheWholeWord);
        run("gaplessOrTooLooseLinesHyphenateInstead", ProgressiveBreakDecisionsCoverageTest.gaplessOrTooLooseLinesHyphenateInstead);
        TestTraceRecorder.flushClass("ProgressiveBreakDecisionsCoverageTest");
        run("infiniteLineLimitWithClustersAdmitsTheCleanestTier", ProgressiveBreakDecisionsTailTest.infiniteLineLimitWithClustersAdmitsTheCleanestTier);
        run("infiniteStretchCeilingWithFiniteLineLimitAdmitsTheCleanestTier",
            ProgressiveBreakDecisionsTailTest.infiniteStretchCeilingWithFiniteLineLimitAdmitsTheCleanestTier);
        TestTraceRecorder.flushClass("ProgressiveBreakDecisionsTailTest");
        run("chargesAllDeficitToCjkWhenNoSinoWesternCapacityIsKnown", DecideHyphenBreakTest.chargesAllDeficitToCjkWhenNoSinoWesternCapacityIsKnown);
        run("discountsSinoWesternCapacityBeforeChargingCjkLooseness", DecideHyphenBreakTest.discountsSinoWesternCapacityBeforeChargingCjkLooseness);
        TestTraceRecorder.flushClass("DecideHyphenBreakTest");
        run("testBundledHyphenationResource", LineBreakCoverageTest.testBundledHyphenationResource);
        run("testLineBreakModelsAndEnums", LineBreakCoverageTest.testLineBreakModelsAndEnums);
        run("testMandatoryBreakAndZeroWidthSpaceCodePoints", LineBreakCoverageTest.testMandatoryBreakAndZeroWidthSpaceCodePoints);
        run("testSimpleCharacterLineBreakAnalyzer", LineBreakCoverageTest.testSimpleCharacterLineBreakAnalyzer);
        run("testHyphenationComponents", LineBreakCoverageTest.testHyphenationComponents);
        run("testUnicodePunctuationLineBreak", LineBreakCoverageTest.testUnicodePunctuationLineBreak);
        TestTraceRecorder.flushClass("LineBreakCoverageTest");
        run("recognizesMandatoryBreakCodePoints", MandatoryBreakTest.recognizesMandatoryBreakCodePoints);
        run("recognizesZeroWidthSpaceWithoutConflatingNoBreakControls", MandatoryBreakTest.recognizesZeroWidthSpaceWithoutConflatingNoBreakControls);
        run("marksRequiredAfterLineFeed", MandatoryBreakTest.marksRequiredAfterLineFeed);
        run("collapsesCrlfToASingleBreakAfterLf", MandatoryBreakTest.collapsesCrlfToASingleBreakAfterLf);
        run("preservesEachBlankLineBreak", MandatoryBreakTest.preservesEachBlankLineBreak);
        TestTraceRecorder.flushClass("MandatoryBreakTest");
        run("lookupClassesCoverTheUaxTailorablePunctuationClasses",
            UnicodePunctuationLineBreakCoverageTest.lookupClassesCoverTheUaxTailorablePunctuationClasses);
        run("nonScalarCodePointsAreRejected", UnicodePunctuationLineBreakCoverageTest.nonScalarCodePointsAreRejected);
        TestTraceRecorder.flushClass("UnicodePunctuationLineBreakCoverageTest");
        run("exposesPinnedWesternAndCjkPunctuationClasses", UnicodePunctuationLineBreakTest.exposesPinnedWesternAndCjkPunctuationClasses);
        run("ordinaryLettersAreOutsideThePunctuationSubset", UnicodePunctuationLineBreakTest.ordinaryLettersAreOutsideThePunctuationSubset);
        TestTraceRecorder.flushClass("UnicodePunctuationLineBreakTest");

        run("exposesLength", TextRangeTest.exposesLength);
        run("rejectsNegativeStart", TextRangeTest.rejectsNegativeStart);
        TestTraceRecorder.flushClass("TextRangeTest");
        run("icPlusReturnsSum", CoreUnitsGeometryTest.icPlusReturnsSum);
        run("icUnaryMinusReturnsNegated", CoreUnitsGeometryTest.icUnaryMinusReturnsNegated);
        run("floatIcExtensionCreatesIc", CoreUnitsGeometryTest.floatIcExtensionCreatesIc);
        run("intIcExtensionCreatesIc", CoreUnitsGeometryTest.intIcExtensionCreatesIc);
        run("icToPxMultipliesByEmSize", CoreUnitsGeometryTest.icToPxMultipliesByEmSize);
        run("rectHeightReturnsDifference", CoreUnitsGeometryTest.rectHeightReturnsDifference);
        run("rectWidthReturnsDifference", CoreUnitsGeometryTest.rectWidthReturnsDifference);
        run("textRangeRejectsStartGreaterThanEnd", CoreUnitsGeometryTest.textRangeRejectsStartGreaterThanEnd);
        run("textRangeRejectsNegativeStart", CoreUnitsGeometryTest.textRangeRejectsNegativeStart);
        run("layoutConstraintsRejectsNonPositiveMaxWidth", CoreUnitsGeometryTest.layoutConstraintsRejectsNonPositiveMaxWidth);
        run("layoutConstraintsRejectsNonPositiveMaxHeight", CoreUnitsGeometryTest.layoutConstraintsRejectsNonPositiveMaxHeight);
        run("layoutConstraintsRejectsNonPositiveMaxLines", CoreUnitsGeometryTest.layoutConstraintsRejectsNonPositiveMaxLines);
        run("maxLinesDecisionInfoRecordsTruncationDetails", CoreUnitsGeometryTest.maxLinesDecisionInfoRecordsTruncationDetails);
        run("layoutDebugInfoAcceptsMaxLinesDecision", CoreUnitsGeometryTest.layoutDebugInfoAcceptsMaxLinesDecision);
        TestTraceRecorder.flushClass("CoreUnitsGeometryTest");
        run("positionedClusterHeightReturnsDifference", CoreLayoutQueriesGapsTest.positionedClusterHeightReturnsDifference);
        run("getLineForOffsetUsesNearestLineWhenGapBetweenLines", CoreLayoutQueriesGapsTest.getLineForOffsetUsesNearestLineWhenGapBetweenLines);
        run("getBoundingBoxesIntDelegatesToTextRange", CoreLayoutQueriesGapsTest.getBoundingBoxesIntDelegatesToTextRange);
        run("richTextBackgroundUsesHorizontalPadding", CoreLayoutQueriesGapsTest.richTextBackgroundUsesHorizontalPadding);
        run("richTextBackgroundTrailingPaddingWhenSpanEndsAtSegmentEnd", CoreLayoutQueriesGapsTest.richTextBackgroundTrailingPaddingWhenSpanEndsAtSegmentEnd);
        run("richTextBackgroundUniformParagraphStyleUsesParagraphStyle", CoreLayoutQueriesGapsTest.richTextBackgroundUniformParagraphStyleUsesParagraphStyle);
        run("markedFaceVerticalBoundsUsesFallbackWhenNoMetricMatches", CoreLayoutQueriesGapsTest.markedFaceVerticalBoundsUsesFallbackWhenNoMetricMatches);
        run("getSelectionOffsetForPositionReturnsNearestWhenBeforeFirstCluster",
            CoreLayoutQueriesGapsTest.getSelectionOffsetForPositionReturnsNearestWhenBeforeFirstCluster);
        run("getSelectionOffsetForPositionReturnsNearestWhenAfterLastCluster",
            CoreLayoutQueriesGapsTest.getSelectionOffsetForPositionReturnsNearestWhenAfterLastCluster);
        run("getSelectionOffsetForPositionReturnsStartOfLineWhenClustersEmpty",
            CoreLayoutQueriesGapsTest.getSelectionOffsetForPositionReturnsStartOfLineWhenClustersEmpty);
        run("getSelectionWordBoundaryForEmojiZwjSequence", CoreLayoutQueriesGapsTest.getSelectionWordBoundaryForEmojiZwjSequence);
        run("getSelectionWordBoundaryForPunctuationReturnsSingle", CoreLayoutQueriesGapsTest.getSelectionWordBoundaryForPunctuationReturnsSingle);
        run("positionedClustersProducesSourceStopsForLatinRun", CoreLayoutQueriesGapsTest.positionedClustersProducesSourceStopsForLatinRun);
        run("offsetForXUsesSourceStopsWhenAvailable", CoreLayoutQueriesGapsTest.offsetForXUsesSourceStopsWhenAvailable);
        run("getBoundingBoxesEmptyRangeReturnsEmptyList", CoreLayoutQueriesGapsTest.getBoundingBoxesEmptyRangeReturnsEmptyList);
        run("getLineForOffsetReturnsNearestLine", CoreLayoutQueriesGapsTest.getLineForOffsetReturnsNearestLine);
        run("getCursorRectReturnsCaretInCluster", CoreLayoutQueriesGapsTest.getCursorRectReturnsCaretInCluster);
        run("getOffsetForPositionUsesMinByWhenOutsideClusters", CoreLayoutQueriesGapsTest.getOffsetForPositionUsesMinByWhenOutsideClusters);
        run("getSelectionWordBoundaryReturnsEmptyForEmptyText", CoreLayoutQueriesGapsTest.getSelectionWordBoundaryReturnsEmptyForEmptyText);
        TestTraceRecorder.flushClass("CoreLayoutQueriesGapsTest");
        run("clipboardProjectionRestoresSourceAndAddsFullySelectedAnnotations",
            LayoutQueriesTest.clipboardProjectionRestoresSourceAndAddsFullySelectedAnnotations);
        run("positionedClustersFollowLineIndentAndAdvance", LayoutQueriesTest.positionedClustersFollowLineIndentAndAdvance);
        run("positionedClustersSeparateOccupiedBoxFromAutoSpaceDrawOrigin", LayoutQueriesTest.positionedClustersSeparateOccupiedBoxFromAutoSpaceDrawOrigin);
        run("positionedClustersSeparateOccupiedBoxFromConsumedLeadingGlueDrawOrigin",
            LayoutQueriesTest.positionedClustersSeparateOccupiedBoxFromConsumedLeadingGlueDrawOrigin);
        run("glyphInkBoundsKeepItalicOverhangSeparateFromOccupiedGeometry", LayoutQueriesTest.glyphInkBoundsKeepItalicOverhangSeparateFromOccupiedGeometry);
        run("lineAndBoxQueriesUseTiqianLineGeometry", LayoutQueriesTest.lineAndBoxQueriesUseTiqianLineGeometry);
        run("rangeBoxesSplitMultiUnitClustersBySourceRange", LayoutQueriesTest.rangeBoxesSplitMultiUnitClustersBySourceRange);
        run("richTextSegmentsReusePositionedClusterGeometryAndSplitLines", LayoutQueriesTest.richTextSegmentsReusePositionedClusterGeometryAndSplitLines);
        run("richTextDecorationTrimsOnlyOuterPunctuationGlue", LayoutQueriesTest.richTextDecorationTrimsOnlyOuterPunctuationGlue);
        run("richTextDecorationKeepsPunctuationGlueInsideItsRange", LayoutQueriesTest.richTextDecorationKeepsPunctuationGlueInsideItsRange);
        run("richTextDecorationDoesNotTrimAlreadyConsumedOpeningGlueTwice", LayoutQueriesTest.richTextDecorationDoesNotTrimAlreadyConsumedOpeningGlueTwice);
        run("customLineStylesReuseTheRendererUnderlineHeight", LayoutQueriesTest.customLineStylesReuseTheRendererUnderlineHeight);
        run("lineThroughBisectsTheIdeographicMetricBox", LayoutQueriesTest.lineThroughBisectsTheIdeographicMetricBox);
        run("richTextBackgroundKeepsInternalGapsButTrimsItsOuterLayoutSpace", LayoutQueriesTest.richTextBackgroundKeepsInternalGapsButTrimsItsOuterLayoutSpace);
        run("uniformTextStyleBackgroundIgnoresFallbackFaceHeightAndAddsPadding",
            LayoutQueriesTest.uniformTextStyleBackgroundIgnoresFallbackFaceHeightAndAddsPadding);
        run("backgroundContinuationCornersKeepOnlyTrueSourceEndsFullyRounded",
            LayoutQueriesTest.backgroundContinuationCornersKeepOnlyTrueSourceEndsFullyRounded);
        run("backgroundContinuationRadiusDefaultsToTheAuthoredCornerRadius", LayoutQueriesTest.backgroundContinuationRadiusDefaultsToTheAuthoredCornerRadius);
        run("adjacentBackgroundsWithTheSameStyleShareOneClearance", LayoutQueriesTest.adjacentBackgroundsWithTheSameStyleShareOneClearance);
        run("adjacentLineDecorationsWithTheSameStyleShareOneClearance", LayoutQueriesTest.adjacentLineDecorationsWithTheSameStyleShareOneClearance);
        run("adjacentBackgroundAndUnderlineDoNotAvoidAcrossStyles", LayoutQueriesTest.adjacentBackgroundAndUnderlineDoNotAvoidAcrossStyles);
        run("hitTestingChoosesOffsetFromTiqianClusterAdvances", LayoutQueriesTest.hitTestingChoosesOffsetFromTiqianClusterAdvances);
        run("selectionHitTestingKeepsSupportedSourceSequencesAtomic", LayoutQueriesTest.selectionHitTestingKeepsSupportedSourceSequencesAtomic);
        run("externalSelectionOffsetsRespectDirectionalBoundaryBias", LayoutQueriesTest.externalSelectionOffsetsRespectDirectionalBoundaryBias);
        run("supportedSourceSequenceRemainsAtomicAcrossEngineClusterBoundaries",
            LayoutQueriesTest.supportedSourceSequenceRemainsAtomicAcrossEngineClusterBoundaries);
        run("inlineObjectSourceRangeIsOneSelectionUnit", LayoutQueriesTest.inlineObjectSourceRangeIsOneSelectionUnit);
        run("selectionWordBoundaryExpandsLatinButKeepsHanAtomic", LayoutQueriesTest.selectionWordBoundaryExpandsLatinButKeepsHanAtomic);
        run("rubySelectionGeometryRedistributesAvoidanceSpreadWithoutOverlap",
            LayoutQueriesTest.rubySelectionGeometryRedistributesAvoidanceSpreadWithoutOverlap);
        TestTraceRecorder.flushClass("LayoutQueriesTest");
        run("cornerRadiiPredicatesCoverEveryComparison", LayoutQueriesResidualCoverageTest.cornerRadiiPredicatesCoverEveryComparison);
        run("resolvedCornerRadiiRejectsInvalidInsetsAndResolvesContinuations",
            LayoutQueriesResidualCoverageTest.resolvedCornerRadiiRejectsInvalidInsetsAndResolvesContinuations);
        run("copyProjectionAppendsFullySelectedAnnotationsOnly", LayoutQueriesResidualCoverageTest.copyProjectionAppendsFullySelectedAnnotationsOnly);
        run("positionedClustersByLineRejectsForeignLines", LayoutQueriesResidualCoverageTest.positionedClustersByLineRejectsForeignLines);
        run("glyphInkBoundsSkipsUnmatchedGlyphsAndReturnsNullWithoutInk",
            LayoutQueriesResidualCoverageTest.glyphInkBoundsSkipsUnmatchedGlyphsAndReturnsNullWithoutInk);
        run("emptyLineResultsShortCircuitEveryQuery", LayoutQueriesResidualCoverageTest.emptyLineResultsShortCircuitEveryQuery);
        run("boundingBoxFallsBackToTheCursorRectAtClusterGaps", LayoutQueriesResidualCoverageTest.boundingBoxFallsBackToTheCursorRectAtClusterGaps);
        run("richTextSegmentsSplitOnLineBreaksAndClusterGaps", LayoutQueriesResidualCoverageTest.richTextSegmentsSplitOnLineBreaksAndClusterGaps);
        run("richTextSegmentsSkipZeroLengthClustersBetweenSlices", LayoutQueriesResidualCoverageTest.richTextSegmentsSkipZeroLengthClustersBetweenSlices);
        run("trimmedDecorationSegmentsKeepOnlyDecorationRoles", LayoutQueriesResidualCoverageTest.trimmedDecorationSegmentsKeepOnlyDecorationRoles);
        run("backgroundSegmentsPassThroughUnmatchableSegments", LayoutQueriesResidualCoverageTest.backgroundSegmentsPassThroughUnmatchableSegments);
        run("backgroundSegmentsTrimGlueApplyPaddingAndUseGlyphAdvances",
            LayoutQueriesResidualCoverageTest.backgroundSegmentsTrimGlueApplyPaddingAndUseGlyphAdvances);
        run("markedFacesUseMetricDecisionsWhenTheyCoverTheCluster", LayoutQueriesResidualCoverageTest.markedFacesUseMetricDecisionsWhenTheyCoverTheCluster);
        run("uniformTextStyleFallsBackWhenEveryMetricFieldDiffers", LayoutQueriesResidualCoverageTest.uniformTextStyleFallsBackWhenEveryMetricFieldDiffers);
        run("uniformTextStylePrefersIdeographicMetricsThenAnyMatchingFace",
            LayoutQueriesResidualCoverageTest.uniformTextStylePrefersIdeographicMetricsThenAnyMatchingFace);
        run("adjacentSameStyleSegmentsShareClearance", LayoutQueriesResidualCoverageTest.adjacentSameStyleSegmentsShareClearance);
        run("decorationLineYRequiresValidStrokeAndDecorationRoles", LayoutQueriesResidualCoverageTest.decorationLineYRequiresValidStrokeAndDecorationRoles);
        run("cursorRectCoversEmptyLinesEmptyClustersAndMultiUnitClusters",
            LayoutQueriesResidualCoverageTest.cursorRectCoversEmptyLinesEmptyClustersAndMultiUnitClusters);
        run("offsetForPositionCoversVerticalDistancesAndNaNPoints", LayoutQueriesResidualCoverageTest.offsetForPositionCoversVerticalDistancesAndNaNPoints);
        run("selectionSnapPrefersTheCloserInlineObjectBoundary", LayoutQueriesResidualCoverageTest.selectionSnapPrefersTheCloserInlineObjectBoundary);
        run("selectionWordBoundaryForPositionRejectsDegenerateContent",
            LayoutQueriesResidualCoverageTest.selectionWordBoundaryForPositionRejectsDegenerateContent);
        run("zeroWidthClustersReturnTheirStartInHitTests", LayoutQueriesResidualCoverageTest.zeroWidthClustersReturnTheirStartInHitTests);
        run("coerceSelectionOffsetHonoursInlineObjectBoundaries", LayoutQueriesResidualCoverageTest.coerceSelectionOffsetHonoursInlineObjectBoundaries);
        run("selectionWordBoundaryExpandsWordsAndHonoursInlineObjects",
            LayoutQueriesResidualCoverageTest.selectionWordBoundaryExpandsWordsAndHonoursInlineObjects);
        run("selectionWordKindCoversEveryHanBlock", LayoutQueriesResidualCoverageTest.selectionWordKindCoversEveryHanBlock);
        run("nearestLineFallsBackToTheOnlyLineAtItsEndOffset", LayoutQueriesResidualCoverageTest.nearestLineFallsBackToTheOnlyLineAtItsEndOffset);
        run("rubyGeometryRedistributesSelectionBoxesAndDropsSourceStops",
            LayoutQueriesResidualCoverageTest.rubyGeometryRedistributesSelectionBoxesAndDropsSourceStops);
        run("boundingBoxesSliceZeroWidthAndEmptyClusters", LayoutQueriesResidualCoverageTest.boundingBoxesSliceZeroWidthAndEmptyClusters);
        run("positionedClustersAndSegmentsReturnEmptyWithoutLines", LayoutQueriesResidualCoverageTest.positionedClustersAndSegmentsReturnEmptyWithoutLines);
        run("sameSpanSlicesAcrossASourceBoundaryMergeIntoOneSegment", LayoutQueriesResidualCoverageTest.sameSpanSlicesAcrossASourceBoundaryMergeIntoOneSegment);
        run("glyphInkBoundsSkipsUnusableGlyphsAndReportsNull", LayoutQueriesResidualCoverageTest.glyphInkBoundsSkipsUnusableGlyphsAndReportsNull);
        run("backgroundTrailingEdgeUsesGlyphAdvancesWhenAvailable", LayoutQueriesResidualCoverageTest.backgroundTrailingEdgeUsesGlyphAdvancesWhenAvailable);
        run("clearanceNeedsSameRoleAndUsesTheSmallerSide", LayoutQueriesResidualCoverageTest.clearanceNeedsSameRoleAndUsesTheSmallerSide);
        run("metricDecisionsMustFullyContainTheCluster", LayoutQueriesResidualCoverageTest.metricDecisionsMustFullyContainTheCluster);
        run("decorationStyleResolvesInsideSpansAndAtTheirEdges", LayoutQueriesResidualCoverageTest.decorationStyleResolvesInsideSpansAndAtTheirEdges);
        run("glueTrimSkipsInteriorSegmentEdges", LayoutQueriesResidualCoverageTest.glueTrimSkipsInteriorSegmentEdges);
        run("backgroundSegmentOutsideEverySpanUsesTheParagraphStyle", LayoutQueriesResidualCoverageTest.backgroundSegmentOutsideEverySpanUsesTheParagraphStyle);
        run("cursorRectFindsLaterClustersAndRejectsGappedRanges", LayoutQueriesResidualCoverageTest.cursorRectFindsLaterClustersAndRejectsGappedRanges);
        run("emptyMidClusterHoldsTheCaretAndSlicesKeepDegenerateRects",
            LayoutQueriesResidualCoverageTest.emptyMidClusterHoldsTheCaretAndSlicesKeepDegenerateRects);
        run("selectionWordBoundarySkipsInlineObjectsItDoesNotContain",
            LayoutQueriesResidualCoverageTest.selectionWordBoundarySkipsInlineObjectsItDoesNotContain);
        run("selectionWordBoundaryForPositionCoversDistancesAndFallbacks",
            LayoutQueriesResidualCoverageTest.selectionWordBoundaryForPositionCoversDistancesAndFallbacks);
        run("lineForOffsetInsideARangeTakesTheZeroDistanceArm", LayoutQueriesResidualCoverageTest.lineForOffsetInsideARangeTakesTheZeroDistanceArm);
        run("compatibilityIdeographsFormIndividualWordUnits", LayoutQueriesResidualCoverageTest.compatibilityIdeographsFormIndividualWordUnits);
        run("rubySpreadShiftsSelectionBoxesAndZeroWidthRubiesAreIgnored",
            LayoutQueriesResidualCoverageTest.rubySpreadShiftsSelectionBoxesAndZeroWidthRubiesAreIgnored);
        run("noArgPositionedClustersWalksEveryLine", LayoutQueriesResidualCoverageTest.noArgPositionedClustersWalksEveryLine);
        run("glyphInkBoundsRejectsEachNonFiniteEdgeIndependently", LayoutQueriesResidualCoverageTest.glyphInkBoundsRejectsEachNonFiniteEdgeIndependently);
        run("clearanceTakesTheSmallerSideWhicheverSegmentOwnsIt", LayoutQueriesResidualCoverageTest.clearanceTakesTheSmallerSideWhicheverSegmentOwnsIt);
        run("uniformTextStylePolicyResolvesSpanStyleOrParagraphStyle",
            LayoutQueriesResidualCoverageTest.uniformTextStylePolicyResolvesSpanStyleOrParagraphStyle);
        run("trailingGlueIsSkippedWhenNoClusterEndsBeforeTheSegmentEnd",
            LayoutQueriesResidualCoverageTest.trailingGlueIsSkippedWhenNoClusterEndsBeforeTheSegmentEnd);
        run("decorationLineYWithoutSpansUsesTheParagraphStyle", LayoutQueriesResidualCoverageTest.decorationLineYWithoutSpansUsesTheParagraphStyle);
        run("wordBoundaryForPositionHandlesANonFiniteY", LayoutQueriesResidualCoverageTest.wordBoundaryForPositionHandlesANonFiniteY);
        run("supplementaryIdeographBeyondTheHanRangesIsItsOwnUnit", LayoutQueriesResidualCoverageTest.supplementaryIdeographBeyondTheHanRangesIsItsOwnUnit);
        run("planeFourCodepointAboveTheHanBandsIsItsOwnUnit", LayoutQueriesResidualCoverageTest.planeFourCodepointAboveTheHanBandsIsItsOwnUnit);
        run("nearestLineSearchCoversAllThreeDistanceArms", LayoutQueriesResidualCoverageTest.nearestLineSearchCoversAllThreeDistanceArms);
        run("rubiesOnOtherLinesDoNotAffectThisLineGeometry", LayoutQueriesResidualCoverageTest.rubiesOnOtherLinesDoNotAffectThisLineGeometry);
        run("backgroundTrailingEdgePicksTheLargestGlyphAdvance", LayoutQueriesResidualCoverageTest.backgroundTrailingEdgePicksTheLargestGlyphAdvance);
        run("backgroundTrailingEdgeKeepsTheFirstGlyphWhenItIsLargest",
            LayoutQueriesResidualCoverageTest.backgroundTrailingEdgeKeepsTheFirstGlyphWhenItIsLargest);
        run("selectionWordBoundaryForPositionPrefersTheCloserLaterLine",
            LayoutQueriesResidualCoverageTest.selectionWordBoundaryForPositionPrefersTheCloserLaterLine);
        run("nearestLineSearchUpdatesToAStrictlyCloserLaterLine", LayoutQueriesResidualCoverageTest.nearestLineSearchUpdatesToAStrictlyCloserLaterLine);
        run("nearestLineSearchCoversBothLambdaCopiesOfEachArm", LayoutQueriesResidualCoverageTest.nearestLineSearchCoversBothLambdaCopiesOfEachArm);
        run("uniformTextStylePolicyPicksTheLastMatchingSpan", LayoutQueriesResidualCoverageTest.uniformTextStylePolicyPicksTheLastMatchingSpan);
        run("decorationLineYPicksTheLastMatchingSpan", LayoutQueriesResidualCoverageTest.decorationLineYPicksTheLastMatchingSpan);
        run("uniformTextStylePolicyKeepsTheEarlierSpanWhenALaterOneMisses",
            LayoutQueriesResidualCoverageTest.uniformTextStylePolicyKeepsTheEarlierSpanWhenALaterOneMisses);
        run("decorationLineYKeepsTheEarlierSpanWhenALaterOneMisses", LayoutQueriesResidualCoverageTest.decorationLineYKeepsTheEarlierSpanWhenALaterOneMisses);
        TestTraceRecorder.flushClass("LayoutQueriesResidualCoverageTest");
        run("coerceToInteractionBoundaryBackwardReturnsBoundaryWhenAtEnd", CoreBoundaryTest.coerceToInteractionBoundaryBackwardReturnsBoundaryWhenAtEnd);
        run("coerceToInteractionBoundaryForwardReturnsNextBoundary", CoreBoundaryTest.coerceToInteractionBoundaryForwardReturnsNextBoundary);
        run("coerceToInteractionBoundaryNearestChoosesCloser", CoreBoundaryTest.coerceToInteractionBoundaryNearestChoosesCloser);
        run("coerceToInteractionBoundaryWithSurrogatePair", CoreBoundaryTest.coerceToInteractionBoundaryWithSurrogatePair);
        run("coerceToInteractionBoundaryWithInvalidSurrogatePair", CoreBoundaryTest.coerceToInteractionBoundaryWithInvalidSurrogatePair);
        run("sourceGraphemeBoundariesWithHangulLeadingJamo", CoreBoundaryTest.sourceGraphemeBoundariesWithHangulLeadingJamo);
        run("sourceGraphemeBoundariesWithHangulSyllable", CoreBoundaryTest.sourceGraphemeBoundariesWithHangulSyllable);
        run("sourceGraphemeBoundariesWithRegionalIndicator", CoreBoundaryTest.sourceGraphemeBoundariesWithRegionalIndicator);
        run("sourceGraphemeBoundariesWithEmojiZwjSequence", CoreBoundaryTest.sourceGraphemeBoundariesWithEmojiZwjSequence);
        run("sourceGraphemeBoundariesWithEmojiModifier", CoreBoundaryTest.sourceGraphemeBoundariesWithEmojiModifier);
        run("sourceGraphemeBoundariesReturnsSingleBoundaryForEmptyText", CoreBoundaryTest.sourceGraphemeBoundariesReturnsSingleBoundaryForEmptyText);
        run("interactionBoundariesWithTextRange", CoreBoundaryTest.interactionBoundariesWithTextRange);
        run("getSelectionOffsetForPositionReturnsStartOfFirstCluster", CoreBoundaryTest.getSelectionOffsetForPositionReturnsStartOfFirstCluster);
        run("getSelectionOffsetForPositionReturnsStartOfLineWhenEmptyClusters",
            CoreBoundaryTest.getSelectionOffsetForPositionReturnsStartOfLineWhenEmptyClusters);
        TestTraceRecorder.flushClass("CoreBoundaryTest");
        run("identicalDisplayAndTargetIsAnAddress", LinkAddressDisplayTest.identicalDisplayAndTargetIsAnAddress);
        run("proseDisplayTextIsNotAnAddress", LinkAddressDisplayTest.proseDisplayTextIsNotAnAddress);
        run("schemeLessDisplayOfTheTargetIsAnAddress", LinkAddressDisplayTest.schemeLessDisplayOfTheTargetIsAnAddress);
        TestTraceRecorder.flushClass("LinkAddressDisplayTest");
        run("crlfStaysOneUnit", SourceInteractionBoundariesCoverageTest.crlfStaysOneUnit);
        run("regionalIndicatorsPairUp", SourceInteractionBoundariesCoverageTest.regionalIndicatorsPairUp);
        run("hangulJamoRunsMergeIntoSyllableBlocks", SourceInteractionBoundariesCoverageTest.hangulJamoRunsMergeIntoSyllableBlocks);
        run("precomposedHangulSyllablesAbsorbJamo", SourceInteractionBoundariesCoverageTest.precomposedHangulSyllablesAbsorbJamo);
        run("extendersAttachToThePrecedingUnit", SourceInteractionBoundariesCoverageTest.extendersAttachToThePrecedingUnit);
        run("bandEdgesAndGapsExerciseEveryRangeArm", SourceInteractionBoundariesCoverageTest.bandEdgesAndGapsExerciseEveryRangeArm);
        run("emojiModifiersOnlyAttachToBases", SourceInteractionBoundariesCoverageTest.emojiModifiersOnlyAttachToBases);
        run("zwjChainsJoinOnlyExtendedPictographic", SourceInteractionBoundariesCoverageTest.zwjChainsJoinOnlyExtendedPictographic);
        run("unpairedSurrogatesFallBackToSingleUnits", SourceInteractionBoundariesCoverageTest.unpairedSurrogatesFallBackToSingleUnits);
        run("codePointAtCompatCoversEverySurrogateCase", SourceInteractionBoundariesCoverageTest.codePointAtCompatCoversEverySurrogateCase);
        run("rangeBoundariesRespectTheRequestedWindow", SourceInteractionBoundariesCoverageTest.rangeBoundariesRespectTheRequestedWindow);
        run("coercionHonoursEveryBiasAndEdgeCase", SourceInteractionBoundariesCoverageTest.coercionHonoursEveryBiasAndEdgeCase);
        TestTraceRecorder.flushClass("SourceInteractionBoundariesCoverageTest");
        run("chineseLanguageContextUsesPinnedMacrolanguageRegistry", EastAsianSpacingTest.chineseLanguageContextUsesPinnedMacrolanguageRegistry);
        run("usesPinnedUnicodeDraftDataAcrossScripts", EastAsianSpacingTest.usesPinnedUnicodeDraftDataAcrossScripts);
        run("resolvesConditionalValuesFromChineseLanguageContext", EastAsianSpacingTest.resolvesConditionalValuesFromChineseLanguageContext);
        run("enclosingMarkMakesTheWholeGraphemeClusterOther", EastAsianSpacingTest.enclosingMarkMakesTheWholeGraphemeClusterOther);
        run("resolvesTheActualSourceUnitAtEachShapingClusterEdge", EastAsianSpacingTest.resolvesTheActualSourceUnitAtEachShapingClusterEdge);
        TestTraceRecorder.flushClass("EastAsianSpacingTest");
        run("testUnicodeWordCharacter", EastAsianSpacingCoverageTest.testUnicodeWordCharacter);
        run("testUnicodeScriptEvidence", EastAsianSpacingCoverageTest.testUnicodeScriptEvidence);
        run("testEastAsianSpacingDataAndValues", EastAsianSpacingCoverageTest.testEastAsianSpacingDataAndValues);
        run("testEastAsianSpacingEdgesModel", EastAsianSpacingCoverageTest.testEastAsianSpacingEdgesModel);
        run("testUnicodeEastAsianSpacing", EastAsianSpacingCoverageTest.testUnicodeEastAsianSpacing);
        TestTraceRecorder.flushClass("EastAsianSpacingCoverageTest");
        run("lookupCoversEveryGeneratedValueAndBothMissDirections", EastAsianSpacingLookupCoverageTest.lookupCoversEveryGeneratedValueAndBothMissDirections);
        TestTraceRecorder.flushClass("EastAsianSpacingLookupCoverageTest");
        run("numbersAreMembersAcrossScriptsAndNonScalarsAreRejected", UnicodeNumberTest.numbersAreMembersAcrossScriptsAndNonScalarsAreRejected);
        TestTraceRecorder.flushClass("UnicodeNumberTest");
        run("commonAndInheritedScalarsDoNotVote", UnicodeScriptEvidenceTest.commonAndInheritedScalarsDoNotVote);
        run("eastAsianScriptsAreDistinctFromOtherStrongScripts", UnicodeScriptEvidenceTest.eastAsianScriptsAreDistinctFromOtherStrongScripts);
        TestTraceRecorder.flushClass("UnicodeScriptEvidenceTest");
        run("lettersAndNumbersAreWordCharactersAcrossScripts", UnicodeWordCharacterTest.lettersAndNumbersAreWordCharactersAcrossScripts);
        TestTraceRecorder.flushClass("UnicodeWordCharacterTest");
        run("testTiqianTextContentAndLinkAddressDisplay", TextModelCoverageTest.testTiqianTextContentAndLinkAddressDisplay);
        run("testSpansAndInlineBox", TextModelCoverageTest.testSpansAndInlineBox);
        run("testInlineObjectPreferredStretchAndAdjustment", TextModelCoverageTest.testInlineObjectPreferredStretchAndAdjustment);
        run("testTextStyleAndDecorations", TextModelCoverageTest.testTextStyleAndDecorations);
        run("testRichTextSpansAndPatterns", TextModelCoverageTest.testRichTextSpansAndPatterns);
        run("testRubyAndParagraphModels", TextModelCoverageTest.testRubyAndParagraphModels);
        TestTraceRecorder.flushClass("TextModelCoverageTest");
        run("yinpingHasNoMark", BopomofoParserTest.yinpingHasNoMark);
        run("suffixMarksAreToneAndStripped", BopomofoParserTest.suffixMarksAreToneAndStripped);
        run("neutralToneIsPrefixed", BopomofoParserTest.neutralToneIsPrefixed);
        run("singleSymbol", BopomofoParserTest.singleSymbol);
        TestTraceRecorder.flushClass("BopomofoParserTest");
        run("bareNumberIsItsOwnGroup", NumberSymbolCohesionTest.bareNumberIsItsOwnGroup);
        run("bindsDigitsWithSuffixUnitPrefixSignAndCurrency", NumberSymbolCohesionTest.bindsDigitsWithSuffixUnitPrefixSignAndCurrency);
        run("keepsInteriorDecimalAndThousandsSeparators", NumberSymbolCohesionTest.keepsInteriorDecimalAndThousandsSeparators);
        TestTraceRecorder.flushClass("NumberSymbolCohesionTest");
        run("noneForbidsNothing", KinsokuLevelTest.noneForbidsNothing);
        run("basicForbidsPauseStopsClosingConnectorsAtStartAndOpeningAtEnd", KinsokuLevelTest.basicForbidsPauseStopsClosingConnectorsAtStartAndOpeningAtEnd);
        run("gbStyleAddsSeparatorAtLineEnd", KinsokuLevelTest.gbStyleAddsSeparatorAtLineEnd);
        run("strictAddsDashAndEllipsisAtLineStart", KinsokuLevelTest.strictAddsDashAndEllipsisAtLineStart);
        run("profileDefaultsToMeasureAdaptive", KinsokuLevelTest.profileDefaultsToMeasureAdaptive);
        run("cjkBracketVariantsClassifyAsOpeningAndClosing", KinsokuLevelTest.cjkBracketVariantsClassifyAsOpeningAndClosing);
        run("exposesUnambiguousAsciiPointMarksWithoutGuessingQuotesOrConnectors",
            KinsokuLevelTest.exposesUnambiguousAsciiPointMarksWithoutGuessingQuotesOrConnectors);
        run("measureAdaptiveResolvesPerLineWidth", KinsokuLevelTest.measureAdaptiveResolvesPerLineWidth);
        TestTraceRecorder.flushClass("KinsokuLevelTest");
        run("mainlandAnchorsClosingAndPauseStopToTrailing", PunctuationGluePlacementTest.mainlandAnchorsClosingAndPauseStopToTrailing);
        run("mainlandAnchorsOpeningToLeading", PunctuationGluePlacementTest.mainlandAnchorsOpeningToLeading);
        run("mainlandSplitsSymmetricPunctuationOnBothSides", PunctuationGluePlacementTest.mainlandSplitsSymmetricPunctuationOnBothSides);
        run("traditionalCentresClosingAndPauseStop", PunctuationGluePlacementTest.traditionalCentresClosingAndPauseStop);
        run("traditionalCentresOpening", PunctuationGluePlacementTest.traditionalCentresOpening);
        run("forRegionMapsClreqRegionsToCorrectPlacement", PunctuationGluePlacementTest.forRegionMapsClreqRegionsToCorrectPlacement);
        run("builtInTaiwanAndHongKongProfilesUseTraditionalPlacement", PunctuationGluePlacementTest.builtInTaiwanAndHongKongProfilesUseTraditionalPlacement);
        TestTraceRecorder.flushClass("PunctuationGluePlacementTest");
        run("preferPolicyUsesClreqRecommendedDisplayCodepoints", ClreqPunctuationGlyphSubstitutorTest.preferPolicyUsesClreqRecommendedDisplayCodepoints);
        run("preservePolicyKeepsInputDisplayCodepoints", ClreqPunctuationGlyphSubstitutorTest.preservePolicyKeepsInputDisplayCodepoints);
        run("preferPolicyDoesNotRewriteAmbiguousConnectorOrSolidusForms",
            ClreqPunctuationGlyphSubstitutorTest.preferPolicyDoesNotRewriteAmbiguousConnectorOrSolidusForms);
        run("recommendedDashCodepointOccupiesTwoEm", ClreqPunctuationGlyphSubstitutorTest.recommendedDashCodepointOccupiesTwoEm);
        TestTraceRecorder.flushClass("ClreqPunctuationGlyphSubstitutorTest");
        run("testBopomofoModelsAndParser", ClreqProfileCoverageTest.testBopomofoModelsAndParser);
        run("testClreqProfileAndResolver", ClreqProfileCoverageTest.testClreqProfileAndResolver);
        run("testClreqPunctuationPoliciesAndClassification", ClreqProfileCoverageTest.testClreqPunctuationPoliciesAndClassification);
        run("testForcedHalfWidthAndPolicyFor", ClreqProfileCoverageTest.testForcedHalfWidthAndPolicyFor);
        run("testForbiddenAtLineStartAndEnd", ClreqProfileCoverageTest.testForbiddenAtLineStartAndEnd);
        run("testPunctuationAdvanceAndSubstitutor", ClreqProfileCoverageTest.testPunctuationAdvanceAndSubstitutor);
        TestTraceRecorder.flushClass("ClreqProfileCoverageTest");
        run("forbiddenAtLineStartCoversEveryPunctuationClass", ClreqPolicyTailCoverageTest.forbiddenAtLineStartCoversEveryPunctuationClass);
        run("forbiddenAtLineEndCoversOpeningSolidusAndOther", ClreqPolicyTailCoverageTest.forbiddenAtLineEndCoversOpeningSolidusAndOther);
        run("kinsokuRuleAllowsClustersWithoutDisplayText", ClreqPolicyTailCoverageTest.kinsokuRuleAllowsClustersWithoutDisplayText);
        run("bopomofoParserCoversEveryToneArm", ClreqPolicyTailCoverageTest.bopomofoParserCoversEveryToneArm);
        TestTraceRecorder.flushClass("ClreqPolicyTailCoverageTest");
        run("nullStatusNamesMissingConformingGlyphAndUnpreparedDetail", CjkDashCapabilityPolicyTest.nullStatusNamesMissingConformingGlyphAndUnpreparedDetail);
        run("conformingStatusWithBlankDetailNamesTheMissingSession", CjkDashCapabilityPolicyTest.conformingStatusWithBlankDetailNamesTheMissingSession);
        run("conformingStatusWithDetailAppendsHostEvidence", CjkDashCapabilityPolicyTest.conformingStatusWithDetailAppendsHostEvidence);
        run("nonConformingStatusWithDetailNamesMissingGlyphAndAppendsEvidence",
            CjkDashCapabilityPolicyTest.nonConformingStatusWithDetailNamesMissingGlyphAndAppendsEvidence);
        run("nonConformingStatusWithBlankDetailKeepsOnlyStatusPrefix", CjkDashCapabilityPolicyTest.nonConformingStatusWithBlankDetailKeepsOnlyStatusPrefix);
        TestTraceRecorder.flushClass("CjkDashCapabilityPolicyTest");
        run("classifiesAsciiBracketsAsLatin", CjkFontRoleClassifierTest.classifiesAsciiBracketsAsLatin);
        run("classifiesAsciiHyphenSlashTildeAsLatinRegardlessOfContext", CjkFontRoleClassifierTest.classifiesAsciiHyphenSlashTildeAsLatinRegardlessOfContext);
        run("classifiesAsciiSymbolsAndPunctuationAsLatin", CjkFontRoleClassifierTest.classifiesAsciiSymbolsAndPunctuationAsLatin);
        run("classifiesCjkPunctuation", CjkFontRoleClassifierTest.classifiesCjkPunctuation);
        run("classifiesCjkText", CjkFontRoleClassifierTest.classifiesCjkText);
        run("classifiesCurlyQuotesAsCjkAtTextBoundary", CjkFontRoleClassifierTest.classifiesCurlyQuotesAsCjkAtTextBoundary);
        run("classifiesCurlyQuotesAsCjkInMixedContext", CjkFontRoleClassifierTest.classifiesCurlyQuotesAsCjkInMixedContext);
        run("classifiesCurlyQuotesAsCjkWhenSurroundedByCjk", CjkFontRoleClassifierTest.classifiesCurlyQuotesAsCjkWhenSurroundedByCjk);
        run("classifiesCurlyQuotesAsLatinWhenSurroundedByLatin", CjkFontRoleClassifierTest.classifiesCurlyQuotesAsLatinWhenSurroundedByLatin);
        run("classifiesLatinText", CjkFontRoleClassifierTest.classifiesLatinText);
        run("classifiesUnicodeEmojiPresentationWithoutReclassifyingPlainKeycapBases",
            CjkFontRoleClassifierTest.classifiesUnicodeEmojiPresentationWithoutReclassifyingPlainKeycapBases);
        TestTraceRecorder.flushClass("CjkFontRoleClassifierTest");
        run("testCjkFontRoleClassifierAllRanges", FontPolicyCoverageTest.testCjkFontRoleClassifierAllRanges);
        run("testFontEnumsAndModels", FontPolicyCoverageTest.testFontEnumsAndModels);
        run("testFontMetricsRequestAndResolvers", FontPolicyCoverageTest.testFontMetricsRequestAndResolvers);
        run("testFontRequestAndRoles", FontPolicyCoverageTest.testFontRequestAndRoles);
        run("testPreferCjkForAmbiguousPunctuationResolver", FontPolicyCoverageTest.testPreferCjkForAmbiguousPunctuationResolver);
        run("testScriptAwareFontMetricsNormalizerBranches", FontPolicyCoverageTest.testScriptAwareFontMetricsNormalizerBranches);
        TestTraceRecorder.flushClass("FontPolicyCoverageTest");

        run("supplementarySymbolIsUnknownBecauseItHasNoBmpCategory", FontRoleTailCoverageTest.supplementarySymbolIsUnknownBecauseItHasNoBmpCategory);
        run("bmpMathAndCurrencySymbolsResolveToSymbolRole", FontRoleTailCoverageTest.bmpMathAndCurrencySymbolsResolveToSymbolRole);
        TestTraceRecorder.flushClass("FontRoleTailCoverageTest");
        run("reportsFirstPropertyWhenItDiverges", InlineShapingStylePolicyTest.reportsFirstPropertyWhenItDiverges);
        run("reportsMiddlePropertyWhenItIsFirstDivergence", InlineShapingStylePolicyTest.reportsMiddlePropertyWhenItIsFirstDivergence);
        run("returnsNullWhenAllValuesMatch", InlineShapingStylePolicyTest.returnsNullWhenAllValuesMatch);
        run("returnsNullForEmptyLists", InlineShapingStylePolicyTest.returnsNullForEmptyLists);
        run("longerValueListsStopAtThePropertyListBoundary", InlineShapingStylePolicyTest.longerValueListsStopAtThePropertyListBoundary);
        TestTraceRecorder.flushClass("InlineShapingStylePolicyTest");
        run("cjkTextUsesFontDeclaredTypoBoxInsteadOfSynthesizedSquare",
            ScriptAwareFontMetricsNormalizerTest.cjkTextUsesFontDeclaredTypoBoxInsteadOfSynthesizedSquare);
        run("cjkTextFallsBackToHheaWhenFontHasNoTypoMetrics", ScriptAwareFontMetricsNormalizerTest.cjkTextFallsBackToHheaWhenFontHasNoTypoMetrics);
        run("latinTextKeepsRomanRawMetrics", ScriptAwareFontMetricsNormalizerTest.latinTextKeepsRomanRawMetrics);
        TestTraceRecorder.flushClass("ScriptAwareFontMetricsNormalizerTest");
        run("onlyLatinTextUsesLatinFace", UsesLatinFaceTest.onlyLatinTextUsesLatinFace);
        run("nameOverloadAgreesWithEnum", UsesLatinFaceTest.nameOverloadAgreesWithEnum);
        TestTraceRecorder.flushClass("UsesLatinFaceTest");
        run("coversAllShapingSourceEnumEntries", TextShaperCoverageTest.coversAllShapingSourceEnumEntries);
        run("unimplementedTextShaperThrowsOnShape", TextShaperCoverageTest.unimplementedTextShaperThrowsOnShape);
        run("explainableStubNominalAdvanceBranches", TextShaperCoverageTest.explainableStubNominalAdvanceBranches);
        run("surrogatePairHandlingInCodePointCount", TextShaperCoverageTest.surrogatePairHandlingInCodePointCount);
        run("shapingInputWithFeaturesAndConstants", TextShaperCoverageTest.shapingInputWithFeaturesAndConstants);
        TestTraceRecorder.flushClass("TextShaperCoverageTest");
        run("shapesSingleCjkClusterWithOneEmAdvance", ExplainableStubTextShaperTest.shapesSingleCjkClusterWithOneEmAdvance);
        run("keepsLatinRunAsSingleShapedClusterWithNominalGlyphs", ExplainableStubTextShaperTest.keepsLatinRunAsSingleShapedClusterWithNominalGlyphs);
        run("shapesClreqDashSubstitutionAsTwoEmDisplayCluster", ExplainableStubTextShaperTest.shapesClreqDashSubstitutionAsTwoEmDisplayCluster);
        TestTraceRecorder.flushClass("ExplainableStubTextShaperTest");
        run("fontFaceIdRejectsBlankAndKeepsValue", ReplayableFontBackendCoverageTest.fontFaceIdRejectsBlankAndKeepsValue);
        run("faceDescriptorDefaultsAreStable", ReplayableFontBackendCoverageTest.faceDescriptorDefaultsAreStable);
        run("faceRequestRejectsNonPositiveAndNonFiniteFontSize", ReplayableFontBackendCoverageTest.faceRequestRejectsNonPositiveAndNonFiniteFontSize);
        run("capabilityReportReplayFlagRequiresFacesAndNoMissingFaceIssue",
            ReplayableFontBackendCoverageTest.capabilityReportReplayFlagRequiresFacesAndNoMissingFaceIssue);
        run("catalogContractResolvesByRequest", ReplayableFontBackendCoverageTest.catalogContractResolvesByRequest);
        TestTraceRecorder.flushClass("ReplayableFontBackendCoverageTest");

        run("glueRejectsInvertedBounds", PunctuationModelCoverageTest.glueRejectsInvertedBounds);
        run("adjustmentOpportunityCarriesRangeAndGlue", PunctuationModelCoverageTest.adjustmentOpportunityCarriesRangeAndGlue);
        run("compressionResultSumsAdjustmentReductions", PunctuationModelCoverageTest.compressionResultSumsAdjustmentReductions);
        run("adjacentPunctuationInnerGlueCollapsesByHalfEm", PunctuationModelCoverageTest.adjacentPunctuationInnerGlueCollapsesByHalfEm);
        run("adjacentPunctuationTargetsTheWiderSide", PunctuationModelCoverageTest.adjacentPunctuationTargetsTheWiderSide);
        run("adjacentPunctuationSkipsNonAdjacentZeroGlueAndZeroEm", PunctuationModelCoverageTest.adjacentPunctuationSkipsNonAdjacentZeroGlueAndZeroEm);
        run("cjkClosingBeforeAsciiPointMarkCollapsesTrailingGlue", PunctuationModelCoverageTest.cjkClosingBeforeAsciiPointMarkCollapsesTrailingGlue);
        run("cjkClosingCompressionRejectsNonMatchingNeighbours", PunctuationModelCoverageTest.cjkClosingCompressionRejectsNonMatchingNeighbours);
        run("indexedBuildRejectsOutOfRangeIndex", PunctuationModelCoverageTest.indexedBuildRejectsOutOfRangeIndex);
        run("nonPunctuationCharactersProduceNoAtom", PunctuationModelCoverageTest.nonPunctuationCharactersProduceNoAtom);
        run("policyFallbackSplitsGlueByClassSide", PunctuationModelCoverageTest.policyFallbackSplitsGlueByClassSide);
        run("underwidthGlyphsExpandIntoFullWidthCellByClassSide", PunctuationModelCoverageTest.underwidthGlyphsExpandIntoFullWidthCellByClassSide);
        run("haltFittedCompressionUsesFontMeasurements", PunctuationModelCoverageTest.haltFittedCompressionUsesFontMeasurements);
        run("haltTrimIsLimitedByInkBoundsAndRecordsWhy", PunctuationModelCoverageTest.haltTrimIsLimitedByInkBoundsAndRecordsWhy);
        run("haltAdvanceWithoutPlacementFallsBackToFittedInkOrProfile", PunctuationModelCoverageTest.haltAdvanceWithoutPlacementFallsBackToFittedInkOrProfile);
        run("haltFromProportionalGlyphIsRejected", PunctuationModelCoverageTest.haltFromProportionalGlyphIsRejected);
        run("inkBoundsFittedFramePicksTheNarrowestContainingAnchor", PunctuationModelCoverageTest.inkBoundsFittedFramePicksTheNarrowestContainingAnchor);
        run("forcedHalfWidthConnectorsConsumeGlueUpFront", PunctuationModelCoverageTest.forcedHalfWidthConnectorsConsumeGlueUpFront);
        run("inkInputRecordsWhyBoundsAreMissing", PunctuationModelCoverageTest.inkInputRecordsWhyBoundsAreMissing);
        run("glueSideForMainlandSimplifiedMapsClassesToSides", PunctuationModelCoverageTest.glueSideForMainlandSimplifiedMapsClassesToSides);
        TestTraceRecorder.flushClass("PunctuationModelCoverageTest");
        run("haltAdvanceWithoutPlacementUsesNamedProfileFallback", PunctuationAtomBuilderHaltTest.haltAdvanceWithoutPlacementUsesNamedProfileFallback);
        run("haltPlacementDirectlyDefinesBothCompressionSides", PunctuationAtomBuilderHaltTest.haltPlacementDirectlyDefinesBothCompressionSides);
        run("haltPlacementOverridesRegionalProfileDirection", PunctuationAtomBuilderHaltTest.haltPlacementOverridesRegionalProfileDirection);
        run("defaultInkCapsAHaltTrimThatWouldCutIntoThePaintedGlyph", PunctuationAtomBuilderHaltTest.defaultInkCapsAHaltTrimThatWouldCutIntoThePaintedGlyph);
        run("equalHaltAdvanceFallsThroughToInkBounds", PunctuationAtomBuilderHaltTest.equalHaltAdvanceFallsThroughToInkBounds);
        run("microsoftYaheiCentredCommaCompressesFromBothSides", PunctuationAtomBuilderHaltTest.microsoftYaheiCentredCommaCompressesFromBothSides);
        run("microsoftYaheiBottomLeftStopKeepsItsLeadingSafetyMargin", PunctuationAtomBuilderHaltTest.microsoftYaheiBottomLeftStopKeepsItsLeadingSafetyMargin);
        run("founderHeitiCentredParenthesesStayMirrorImages", PunctuationAtomBuilderHaltTest.founderHeitiCentredParenthesesStayMirrorImages);
        run("underwidthOpeningQuoteCompletesTheLeadingSideOfItsFullWidthCell",
            PunctuationAtomBuilderHaltTest.underwidthOpeningQuoteCompletesTheLeadingSideOfItsFullWidthCell);
        run("fixedHalfConsumesMeasuredSidebearingsInsteadOfApplyingAProfileShift",
            PunctuationAtomBuilderHaltTest.fixedHalfConsumesMeasuredSidebearingsInsteadOfApplyingAProfileShift);
        run("overhangReducesCompressionCapacityWithoutMovingInk", PunctuationAtomBuilderHaltTest.overhangReducesCompressionCapacityWithoutMovingInk);
        TestTraceRecorder.flushClass("PunctuationAtomBuilderHaltTest");
        run("breakCandidateDefaultsAreUsable", LineOptimizationCoverageTest.breakCandidateDefaultsAreUsable);
        run("breakCandidateCarriesExplicitForbiddenReasonAndRepairs", LineOptimizationCoverageTest.breakCandidateCarriesExplicitForbiddenReasonAndRepairs);
        run("lineCandidateRejectsHangingThatIsNotATrailingSuffix", LineOptimizationCoverageTest.lineCandidateRejectsHangingThatIsNotATrailingSuffix);
        run("lineCandidateRejectsDiscontiguousHanging", LineOptimizationCoverageTest.lineCandidateRejectsDiscontiguousHanging);
        run("lineCandidateAcceptsAContiguousTrailingHangingSuffix", LineOptimizationCoverageTest.lineCandidateAcceptsAContiguousTrailingHangingSuffix);
        run("hangingClusterIndexPrefersTheHangOffenderOverTheSuffixEnd",
            LineOptimizationCoverageTest.hangingClusterIndexPrefersTheHangOffenderOverTheSuffixEnd);
        run("inMeasureClusterRangeExcludesTheHangingSuffix", LineOptimizationCoverageTest.inMeasureClusterRangeExcludesTheHangingSuffix);
        run("carryNextRecordsTheMovedMark", LineOptimizationCoverageTest.carryNextRecordsTheMovedMark);
        run("repairCandidateDefaultsAreUsable", LineOptimizationCoverageTest.repairCandidateDefaultsAreUsable);
        run("lineSolutionDefaultsToZeroBadness", LineOptimizationCoverageTest.lineSolutionDefaultsToZeroBadness);
        run("optimizationStrategyEnumeratesAllThreeStrategies", LineOptimizationCoverageTest.optimizationStrategyEnumeratesAllThreeStrategies);
        TestTraceRecorder.flushClass("LineOptimizationCoverageTest");
        run("parentheticalPairWithOnlyLeftOuterScriptTakesTheLeftRole",
            ContextualDashEllipsisRoleResolverCoverageTest.parentheticalPairWithOnlyLeftOuterScriptTakesTheLeftRole);
        run("parentheticalPairWithOnlyRightOuterScriptTakesTheRightRole",
            ContextualDashEllipsisRoleResolverCoverageTest.parentheticalPairWithOnlyRightOuterScriptTakesTheRightRole);
        run("parentheticalPairWithoutOuterScriptFallsBackToParagraphLanguage",
            ContextualDashEllipsisRoleResolverCoverageTest.parentheticalPairWithoutOuterScriptFallsBackToParagraphLanguage);
        run("forwardPassWalkerArmsRunBeforeTheClassifierRejectsLoneSurrogates",
            ContextualDashEllipsisRoleResolverCoverageTest.forwardPassWalkerArmsRunBeforeTheClassifierRejectsLoneSurrogates);
        TestTraceRecorder.flushClass("ContextualDashEllipsisRoleResolverCoverageTest");
        run("resolvesBySurroundingScriptRatherThanMarkCount", ContextualDashEllipsisRoleResolverTest.resolvesBySurroundingScriptRatherThanMarkCount);
        run("conflictingOrAbsentScriptFallsBackToParagraphLanguage",
            ContextualDashEllipsisRoleResolverTest.conflictingOrAbsentScriptFallsBackToParagraphLanguage);
        run("decisionReasonNamesTheEvidenceShape", ContextualDashEllipsisRoleResolverTest.decisionReasonNamesTheEvidenceShape);
        run("mandatoryBreakStopsContextSearch", ContextualDashEllipsisRoleResolverTest.mandatoryBreakStopsContextSearch);
        run("linearContextIndexPreservesSupplementaryScriptEvidence",
            ContextualDashEllipsisRoleResolverTest.linearContextIndexPreservesSupplementaryScriptEvidence);
        run("resolvesManyNeutralSeparatedRunsFromOneParagraphIndex",
            ContextualDashEllipsisRoleResolverTest.resolvesManyNeutralSeparatedRunsFromOneParagraphIndex);
        run("pairsParentheticalDashesAcrossInsertedContent", ContextualDashEllipsisRoleResolverTest.pairsParentheticalDashesAcrossInsertedContent);
        run("matchingOuterScriptResolvesTheParentheticalPairDirectly",
            ContextualDashEllipsisRoleResolverTest.matchingOuterScriptResolvesTheParentheticalPairDirectly);
        run("punctuationBetweenRunsKeepsThemIndependent", ContextualDashEllipsisRoleResolverTest.punctuationBetweenRunsKeepsThemIndependent);
        run("symbolBetweenRunsKeepsThemIndependent", ContextualDashEllipsisRoleResolverTest.symbolBetweenRunsKeepsThemIndependent);
        run("unequalRunLengthsDoNotPair", ContextualDashEllipsisRoleResolverTest.unequalRunLengthsDoNotPair);
        run("ellipsisRunsNeverPair", ContextualDashEllipsisRoleResolverTest.ellipsisRunsNeverPair);
        run("mandatoryBreakBetweenRunsKeepsThemIndependent", ContextualDashEllipsisRoleResolverTest.mandatoryBreakBetweenRunsKeepsThemIndependent);
        run("westernContextKeepsDashAndEllipsisOnLatinFaceAndPreservesSourceDisplay",
            ContextualDashEllipsisRoleResolverTest.westernContextKeepsDashAndEllipsisOnLatinFaceAndPreservesSourceDisplay);
        run("cjkContextKeepsClreqDisplaySubstitutionIndependentOfMarkCount",
            ContextualDashEllipsisRoleResolverTest.cjkContextKeepsClreqDisplaySubstitutionIndependentOfMarkCount);
        run("parentheticalPairSharesOneFaceAndSubstitution", ContextualDashEllipsisRoleResolverTest.parentheticalPairSharesOneFaceAndSubstitution);
        run("standaloneWesternEllipsisCannotBeRewrittenByTheSubstitutor",
            ContextualDashEllipsisRoleResolverTest.standaloneWesternEllipsisCannotBeRewrittenByTheSubstitutor);
        run("contextualRoleExtensionsWrapOutsideThePipeline", ContextualRoleExtensionCoverageTest.contextualRoleExtensionsWrapOutsideThePipeline);
        TestTraceRecorder.flushClass("ContextualRoleExtensionCoverageTest");
        run("latinDashRunAtParagraphEndStaysOneCluster", ContextualDashEllipsisClusterCoverageTest.latinDashRunAtParagraphEndStaysOneCluster);
        run("styleSpanInsideLatinDashRunSplitsTheCluster", ContextualDashEllipsisClusterCoverageTest.styleSpanInsideLatinDashRunSplitsTheCluster);
        TestTraceRecorder.flushClass("ContextualDashEllipsisClusterCoverageTest");
        run("nestedPairInheritsEnclosingQuoteRole", ContextualQuoteRoleResolverCoverageTest.nestedPairInheritsEnclosingQuoteRole);
        run("nestedPairLatinInnerInheritsCjkEnclosing", ContextualQuoteRoleResolverCoverageTest.nestedPairLatinInnerInheritsCjkEnclosing);
        run("unmatchedRightSingleQuoteUsesSurroundingScript", ContextualQuoteRoleResolverCoverageTest.unmatchedRightSingleQuoteUsesSurroundingScript);
        run("unmatchedRightDoubleQuote", ContextualQuoteRoleResolverCoverageTest.unmatchedRightDoubleQuote);
        run("unmatchedLeftDoubleQuote", ContextualQuoteRoleResolverCoverageTest.unmatchedLeftDoubleQuote);
        run("unmatchedLeftSingleQuote", ContextualQuoteRoleResolverCoverageTest.unmatchedLeftSingleQuote);
        run("conflictingUnmatchedQuotesUsesParagraphLanguage", ContextualQuoteRoleResolverCoverageTest.conflictingUnmatchedQuotesUsesParagraphLanguage);
        run("unmatchedQuoteWithSurrogatePairContent", ContextualQuoteRoleResolverCoverageTest.unmatchedQuoteWithSurrogatePairContent);
        run("codePointAtCompatWithSupplementaryChar", ContextualQuoteRoleResolverCoverageTest.codePointAtCompatWithSupplementaryChar);
        run("codePointLengthAtSupplementaryInContent", ContextualQuoteRoleResolverCoverageTest.codePointLengthAtSupplementaryInContent);
        run("nonCjkInWordApostropheWithSurrogateBefore", ContextualQuoteRoleResolverCoverageTest.nonCjkInWordApostropheWithSurrogateBefore);
        run("whitespaceDelimitedWesternQuoteUnmatched", ContextualQuoteRoleResolverCoverageTest.whitespaceDelimitedWesternQuoteUnmatched);
        run("enclosingPairResolvedBeforeInner", ContextualQuoteRoleResolverCoverageTest.enclosingPairResolvedBeforeInner);
        run("pairByCloseSkipInNearestStrongScript", ContextualQuoteRoleResolverCoverageTest.pairByCloseSkipInNearestStrongScript);
        run("pairByOpenSkipInNearestStrongScript", ContextualQuoteRoleResolverCoverageTest.pairByOpenSkipInNearestStrongScript);
        run("ambiguousCurlyQuoteUnmatchedInText", ContextualQuoteRoleResolverCoverageTest.ambiguousCurlyQuoteUnmatchedInText);
        run("resolveUnmatchedWithBothSurroundingRolesNull", ContextualQuoteRoleResolverCoverageTest.resolveUnmatchedWithBothSurroundingRolesNull);
        run("nearestStrongScriptRoleBackwardSkipsPairedCloseQuote",
            ContextualQuoteRoleResolverCoverageTest.nearestStrongScriptRoleBackwardSkipsPairedCloseQuote);
        run("nearestStrongScriptRoleForwardSkipsPairedOpenQuote", ContextualQuoteRoleResolverCoverageTest.nearestStrongScriptRoleForwardSkipsPairedOpenQuote);
        run("enclosingPairResolvedBeforeInnerPair", ContextualQuoteRoleResolverCoverageTest.enclosingPairResolvedBeforeInnerPair);
        run("whitespaceDelimitedWesternQuotePaired", ContextualQuoteRoleResolverCoverageTest.whitespaceDelimitedWesternQuotePaired);
        run("conflictingUnmatchedQuotesBothNonNull", ContextualQuoteRoleResolverCoverageTest.conflictingUnmatchedQuotesBothNonNull);
        run("noUnmatchedQuoteContext", ContextualQuoteRoleResolverCoverageTest.noUnmatchedQuoteContext);
        run("nearestStrongScriptRoleBackwardThroughSurrogatePair", ContextualQuoteRoleResolverCoverageTest.nearestStrongScriptRoleBackwardThroughSurrogatePair);
        run("nearestStrongScriptRoleForwardThroughSurrogatePair", ContextualQuoteRoleResolverCoverageTest.nearestStrongScriptRoleForwardThroughSurrogatePair);
        run("nestedPairSkipsInnerInScriptEvidence", ContextualQuoteRoleResolverCoverageTest.nestedPairSkipsInnerInScriptEvidence);
        run("mixedScriptEnclosingLevelUsesParagraphLanguage", ContextualQuoteRoleResolverCoverageTest.mixedScriptEnclosingLevelUsesParagraphLanguage);
        run("unmatchedRightSingleQuoteWithLeftRole", ContextualQuoteRoleResolverCoverageTest.unmatchedRightSingleQuoteWithLeftRole);
        run("unmatchedRightSingleQuoteWithRightRole", ContextualQuoteRoleResolverCoverageTest.unmatchedRightSingleQuoteWithRightRole);
        run("unmatchedQuoteWithWhitespaceBeforeAndLatinRight", ContextualQuoteRoleResolverCoverageTest.unmatchedQuoteWithWhitespaceBeforeAndLatinRight);
        run("nonCjkInWordApostrophePaired", ContextualQuoteRoleResolverCoverageTest.nonCjkInWordApostrophePaired);
        run("codePointLengthAtSurrogatePairInContent", ContextualQuoteRoleResolverCoverageTest.codePointLengthAtSurrogatePairInContent);
        run("codePointAtCompatSupplementaryInOuterEvidence", ContextualQuoteRoleResolverCoverageTest.codePointAtCompatSupplementaryInOuterEvidence);
        run("conflictingUnmatchedQuotesLeftAndRightNonNull", ContextualQuoteRoleResolverCoverageTest.conflictingUnmatchedQuotesLeftAndRightNonNull);
        run("unmatchedQuoteNonWhitespaceBefore", ContextualQuoteRoleResolverCoverageTest.unmatchedQuoteNonWhitespaceBefore);
        run("nearestStrongScriptRoleBackwardHitsSupplementary", ContextualQuoteRoleResolverCoverageTest.nearestStrongScriptRoleBackwardHitsSupplementary);
        run("nearestStrongScriptRoleForwardHitsSupplementary", ContextualQuoteRoleResolverCoverageTest.nearestStrongScriptRoleForwardHitsSupplementary);
        run("enclosingPairUnresolvedFallsThroughToContent", ContextualQuoteRoleResolverCoverageTest.enclosingPairUnresolvedFallsThroughToContent);
        run("unmatchedQuoteAtStartWithRightRole", ContextualQuoteRoleResolverCoverageTest.unmatchedQuoteAtStartWithRightRole);
        TestTraceRecorder.flushClass("ContextualQuoteRoleResolverCoverageTest");
        run("nestedPairInsideNeutralEnclosingInheritsTheOuterQuotation",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.nestedPairInsideNeutralEnclosingInheritsTheOuterQuotation);
        run("spaceBeforeUnmatchedQuoteWithCjkRightSkipsTheDelimitedRule",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.spaceBeforeUnmatchedQuoteWithCjkRightSkipsTheDelimitedRule);
        run("leftwardScanFromALowSurrogateWalksEveryBacktrackArm",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.leftwardScanFromALowSurrogateWalksEveryBacktrackArm);
        run("tabBeforeAWhollyWesternPairDelimitsLikeASpace", ContextualQuoteRoleResolverNestedAndSurrogateTest.tabBeforeAWhollyWesternPairDelimitsLikeASpace);
        run("spaceBeforeAPairWithNonWesternContentSkipsTheDelimitedRule",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.spaceBeforeAPairWithNonWesternContentSkipsTheDelimitedRule);
        run("spaceBeforeAMixedContentPairReportsMixedContent",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.spaceBeforeAMixedContentPairReportsMixedContent);
        run("mixedEnclosingLevelFallsBackToParagraphLanguage",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.mixedEnclosingLevelFallsBackToParagraphLanguage);
        run("nonChineseLocaleResolvesNeutralContextToLatinText",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.nonChineseLocaleResolvesNeutralContextToLatinText);
        run("privateUseCharBeforeAQuoteFailsTheLowSurrogateRangeAbove",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.privateUseCharBeforeAQuoteFailsTheLowSurrogateRangeAbove);
        run("highSurrogateAtTheContentEndHasNoRoomAndThrows", ContextualQuoteRoleResolverNestedAndSurrogateTest.highSurrogateAtTheContentEndHasNoRoomAndThrows);
        run("siblingPairsInsideOneQuotationEachInheritTheOuterRole",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.siblingPairsInsideOneQuotationEachInheritTheOuterRole);
        run("plainFollowerOfAHighSurrogateCountsAsOneUnit", ContextualQuoteRoleResolverNestedAndSurrogateTest.plainFollowerOfAHighSurrogateCountsAsOneUnit);
        run("privateUseFollowerOfAHighSurrogateCountsAsOneUnit",
            ContextualQuoteRoleResolverNestedAndSurrogateTest.privateUseFollowerOfAHighSurrogateCountsAsOneUnit);
        TestTraceRecorder.flushClass("ContextualQuoteRoleResolverNestedAndSurrogateTest");
        run("clusterRoleRangesModifierBaseWithVariationSelectorAndModifier",
            ClusterRoleResolutionCoverageTest.clusterRoleRangesModifierBaseWithVariationSelectorAndModifier);
        run("clusterRoleRangesWithAsciiPointMark", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithAsciiPointMark);
        run("clusterRoleRangesWithAsciiPointMarkAttached", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithAsciiPointMarkAttached);
        run("clusterRoleRangesWithAttachedAsciiPointMarkAtStart", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithAttachedAsciiPointMarkAtStart);
        run("clusterRoleRangesWithAttachedAsciiPointMarkFollowedByLatin",
            ClusterRoleResolutionCoverageTest.clusterRoleRangesWithAttachedAsciiPointMarkFollowedByLatin);
        run("clusterRoleRangesWithAttachedAsciiPointMarkNotAdjacent", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithAttachedAsciiPointMarkNotAdjacent);
        run("clusterRoleRangesWithCjkPunctuationAndCoalesce", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCjkPunctuationAndCoalesce);
        run("clusterRoleRangesWithCjkPunctuationCoalesce", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCjkPunctuationCoalesce);
        run("clusterRoleRangesWithCoalesceRepeatablePunctuation", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCoalesceRepeatablePunctuation);
        run("clusterRoleRangesWithCrAtEnd", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCrAtEnd);
        run("clusterRoleRangesWithCrNotFollowedByLf", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCrNotFollowedByLf);
        run("clusterRoleRangesWithCrOnly", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCrOnly);
        run("clusterRoleRangesWithCrlfMandatoryBreak", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCrlfMandatoryBreak);
        run("clusterRoleRangesWithCrlfOnly", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCrlfOnly);
        run("clusterRoleRangesWithCrlfPairProducesSingleCluster", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithCrlfPairProducesSingleCluster);
        run("clusterRoleRangesWithEmoji", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmoji);
        run("clusterRoleRangesWithEmojiModifierBaseCombiningMark", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiModifierBaseCombiningMark);
        run("clusterRoleRangesWithEmojiModifierSequence", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiModifierSequence);
        run("clusterRoleRangesWithEmojiRolePromotionNull", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiRolePromotionNull);
        run("clusterRoleRangesWithEmojiShapingBoundaries", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiShapingBoundaries);
        run("clusterRoleRangesWithEmojiShapingBoundaryAtGraphemeEnd", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiShapingBoundaryAtGraphemeEnd);
        run("clusterRoleRangesWithEmojiShapingBoundaryInside", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiShapingBoundaryInside);
        run("clusterRoleRangesWithEmojiShapingBoundaryInsideAndOutsideRange",
            ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiShapingBoundaryInsideAndOutsideRange);
        run("clusterRoleRangesWithEmojiStyleVariation", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiStyleVariation);
        run("clusterRoleRangesWithEmojiStyleVariationNoFE0F", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiStyleVariationNoFE0F);
        run("clusterRoleRangesWithEmojiVariationAndModifier", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmojiVariationAndModifier);
        run("clusterRoleRangesWithEmptyText", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithEmptyText);
        run("clusterRoleRangesWithGraphemeExtend", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithGraphemeExtend);
        run("clusterRoleRangesWithGraphemeExtendAfterEmoji", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithGraphemeExtendAfterEmoji);
        run("clusterRoleRangesWithInlineObject", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithInlineObject);
        run("clusterRoleRangesWithKeycapBaseAndKeycap", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithKeycapBaseAndKeycap);
        run("clusterRoleRangesWithKeycapBaseNoKeycap", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithKeycapBaseNoKeycap);
        run("clusterRoleRangesWithKeycapSequence", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithKeycapSequence);
        run("clusterRoleRangesWithLfAtStart", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithLfAtStart);
        run("clusterRoleRangesWithLfInsideCrlf", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithLfInsideCrlf);
        run("clusterRoleRangesWithLfOnly", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithLfOnly);
        run("clusterRoleRangesWithLoneSurrogate", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithLoneSurrogate);
        run("clusterRoleRangesWithLoneSurrogateHighOnly", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithLoneSurrogateHighOnly);
        run("clusterRoleRangesWithMultipleEmojiShapingBoundaries", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithMultipleEmojiShapingBoundaries);
        run("clusterRoleRangesWithMultipleSpanBoundaries", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithMultipleSpanBoundaries);
        run("clusterRoleRangesWithNonAsciiPointMark", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithNonAsciiPointMark);
        run("clusterRoleRangesWithNonCjkPunctuation", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithNonCjkPunctuation);
        run("clusterRoleRangesWithNonCombiningMark", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithNonCombiningMark);
        run("clusterRoleRangesWithNonVariationSelector", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithNonVariationSelector);
        run("clusterRoleRangesWithOnlyWhitespace", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithOnlyWhitespace);
        run("clusterRoleRangesWithRoleOverride", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithRoleOverride);
        run("clusterRoleRangesWithSimpleText", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithSimpleText);
        run("clusterRoleRangesWithSingleGrapheme", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithSingleGrapheme);
        run("clusterRoleRangesWithSpanBoundaries", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithSpanBoundaries);
        run("clusterRoleRangesWithSupplementaryCharacter", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithSupplementaryCharacter);
        run("clusterRoleRangesWithSurrogatePairNonLow", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithSurrogatePairNonLow);
        run("clusterRoleRangesWithVariationSelector", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithVariationSelector);
        run("clusterRoleRangesWithVariationSelectorAfterEmoji", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithVariationSelectorAfterEmoji);
        run("clusterRoleRangesWithVariationSelectorAfterLatin", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithVariationSelectorAfterLatin);
        run("clusterRoleRangesWithZWJSequence", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithZWJSequence);
        run("clusterRoleRangesWithZeroWidthSpace", ClusterRoleResolutionCoverageTest.clusterRoleRangesWithZeroWidthSpace);
        run("requireCoveredByFailsWhenClusterCrossesDecisionRange", ClusterRoleResolutionCoverageTest.requireCoveredByFailsWhenClusterCrossesDecisionRange);
        run("requireCoveredByFailsWhenClustersAreNonContiguous", ClusterRoleResolutionCoverageTest.requireCoveredByFailsWhenClustersAreNonContiguous);
        run("requireCoveredByFailsWhenClustersDoNotCoverEnd", ClusterRoleResolutionCoverageTest.requireCoveredByFailsWhenClustersDoNotCoverEnd);
        run("requireCoveredByWithContiguousClusters", ClusterRoleResolutionCoverageTest.requireCoveredByWithContiguousClusters);
        run("requireCoveredByWithEmptyDecisions", ClusterRoleResolutionCoverageTest.requireCoveredByWithEmptyDecisions);
        run("requireCoveredByWithGapBetweenDecisions", ClusterRoleResolutionCoverageTest.requireCoveredByWithGapBetweenDecisions);
        run("requireCoveredByWithMultipleDecisions", ClusterRoleResolutionCoverageTest.requireCoveredByWithMultipleDecisions);
        run("requireCoveredByWithOverlappingDecisions", ClusterRoleResolutionCoverageTest.requireCoveredByWithOverlappingDecisions);
        run("requireCoveredByWithSingleCluster", ClusterRoleResolutionCoverageTest.requireCoveredByWithSingleCluster);
        TestTraceRecorder.flushClass("ClusterRoleResolutionCoverageTest");
        run("astralVariationSelectorAfterAnAttachedPointMarkEndsTheRun",
            ClusterRoleResolutionSurrogateAndExtenderEdgeTest.astralVariationSelectorAfterAnAttachedPointMarkEndsTheRun);
        run("astralVariationSelectorBetweenBaseAndModifierKeepsTheSequence",
            ClusterRoleResolutionSurrogateAndExtenderEdgeTest.astralVariationSelectorBetweenBaseAndModifierKeepsTheSequence);
        run("astralVariationSelectorExtendsTheRunBeforeIt", ClusterRoleResolutionSurrogateAndExtenderEdgeTest.astralVariationSelectorExtendsTheRunBeforeIt);
        run("codePointAboveTheSupplementarySelectorRangeStandsAlone",
            ClusterRoleResolutionSurrogateAndExtenderEdgeTest.codePointAboveTheSupplementarySelectorRangeStandsAlone);
        run("highSurrogateBeforePlainBmpKeepsTheLoneHalf", ClusterRoleResolutionSurrogateAndExtenderEdgeTest.highSurrogateBeforePlainBmpKeepsTheLoneHalf);
        run("highSurrogateBeforePrivateUseKeepsTheLoneHalf", ClusterRoleResolutionSurrogateAndExtenderEdgeTest.highSurrogateBeforePrivateUseKeepsTheLoneHalf);
        run("inlineObjectOverTheCrWalksTheLfWithACrBehindIt", ClusterRoleResolutionSurrogateAndExtenderEdgeTest.inlineObjectOverTheCrWalksTheLfWithACrBehindIt);
        run("modifierBaseWithABmpSelectorWalksTheSelectorTrueArm",
            ClusterRoleResolutionSurrogateAndExtenderEdgeTest.modifierBaseWithABmpSelectorWalksTheSelectorTrueArm);
        run("modifierBaseWithOnlyASelectorEndsTheWalkAtTheClusterEnd",
            ClusterRoleResolutionSurrogateAndExtenderEdgeTest.modifierBaseWithOnlyASelectorEndsTheWalkAtTheClusterEnd);
        run("spanBoundaryAfterASpaceLetThePointMarkSeeItsWhitespaceNeighbour",
            ClusterRoleResolutionSurrogateAndExtenderEdgeTest.spanBoundaryAfterASpaceLetThePointMarkSeeItsWhitespaceNeighbour);
        run("zwjMemberInsideAModifierBaseClusterBreaksTheWalkBelowTheRange",
            ClusterRoleResolutionSurrogateAndExtenderEdgeTest.zwjMemberInsideAModifierBaseClusterBreaksTheWalkBelowTheRange);
        TestTraceRecorder.flushClass("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        run("carryPreviousMovesThePreviousTailDownWhenItFits", LineRepairCoverageTest.carryPreviousMovesThePreviousTailDownWhenItFits);
        run("contextualHangExtendsOnlyInsideItsProtectedGroup", LineRepairCoverageTest.contextualHangExtendsOnlyInsideItsProtectedGroup);
        run("defaultArgumentsRunTheFullRaggedChain", LineRepairCoverageTest.defaultArgumentsRunTheFullRaggedChain);
        run("fillPushInAcceptsCompressionDenserThanTheCuredStretch", LineRepairCoverageTest.fillPushInAcceptsCompressionDenserThanTheCuredStretch);
        run("fillPushInDefaultArgumentsOmitTheOptionalBoundaries", LineRepairCoverageTest.fillPushInDefaultArgumentsOmitTheOptionalBoundaries);
        run("fillPushInExtendsPastForbiddenHeadsAndUnbreakableChains", LineRepairCoverageTest.fillPushInExtendsPastForbiddenHeadsAndUnbreakableChains);
        run("fillPushInHonoursProgressiveTierPromotionBoundaries", LineRepairCoverageTest.fillPushInHonoursProgressiveTierPromotionBoundaries);
        run("fillPushInPullsTheGroupAndCascadesZeroShrinkFills", LineRepairCoverageTest.fillPushInPullsTheGroupAndCascadesZeroShrinkFills);
        run("fillPushInRejectsOverlargePullsAndWorseCompressionDensity", LineRepairCoverageTest.fillPushInRejectsOverlargePullsAndWorseCompressionDensity);
        run("fillPushInSkipsFullLinesAndUnpullableGroups", LineRepairCoverageTest.fillPushInSkipsFullLinesAndUnpullableGroups);
        run("fillPushInSkipsRepairedHangingAndNonAutoWrapLines", LineRepairCoverageTest.fillPushInSkipsRepairedHangingAndNonAutoWrapLines);
        run("fillPushInSkipsShortInputsAndZeroBias", LineRepairCoverageTest.fillPushInSkipsShortInputsAndZeroBias);
        run("forbiddenStartOverrideControlsTheKinsokuCheck", LineRepairCoverageTest.forbiddenStartOverrideControlsTheKinsokuCheck);
        run("hangConsumesAZeroWidthMandatoryBreakTail", LineRepairCoverageTest.hangConsumesAZeroWidthMandatoryBreakTail);
        run("hangMergesTheOffenderBeyondTheMeasure", LineRepairCoverageTest.hangMergesTheOffenderBeyondTheMeasure);
        run("hangStopsBeforeANonZeroWidthMandatoryBreakTail", LineRepairCoverageTest.hangStopsBeforeANonZeroWidthMandatoryBreakTail);
        run("leaveRaggedRecordsNoRoomToCarryForASingleClusterLine", LineRepairCoverageTest.leaveRaggedRecordsNoRoomToCarryForASingleClusterLine);
        run("leaveRaggedRefusesCarriesThatWouldSplitAnUnbreakableSpan", LineRepairCoverageTest.leaveRaggedRefusesCarriesThatWouldSplitAnUnbreakableSpan);
        run("mandatoryBreakAndEmptyLinesSkipTheRepairLoop", LineRepairCoverageTest.mandatoryBreakAndEmptyLinesSkipTheRepairLoop);
        run("mandatoryBreakTailEndReturnsTheMergeThroughAtTheLineEnd", LineRepairCoverageTest.mandatoryBreakTailEndReturnsTheMergeThroughAtTheLineEnd);
        run("pushInFiltersOutOfRangeZeroCapacityAndForeignLineEndOnlyOpportunities",
            LineRepairCoverageTest.pushInFiltersOutOfRangeZeroCapacityAndForeignLineEndOnlyOpportunities);
        run("pushInFitsWithoutShrinkWhenTheMergedLineAlreadyMatches", LineRepairCoverageTest.pushInFitsWithoutShrinkWhenTheMergedLineAlreadyMatches);
        run("pushInPromotesTheOffendersOwnTrailingGlueToTierOne", LineRepairCoverageTest.pushInPromotesTheOffendersOwnTrailingGlueToTierOne);
        run("pushInRejectsAMergeThroughClusterOutsideTheCurrentLine", LineRepairCoverageTest.pushInRejectsAMergeThroughClusterOutsideTheCurrentLine);
        run("pushInRejectsMergeThroughOutsideTheCurrentLine", LineRepairCoverageTest.pushInRejectsMergeThroughOutsideTheCurrentLine);
        run("pushInRejectsWhenCapacityIsInsufficient", LineRepairCoverageTest.pushInRejectsWhenCapacityIsInsufficient);
        run("pushInReportsInfinityCapacityWithAPortableDebugString", LineRepairCoverageTest.pushInReportsInfinityCapacityWithAPortableDebugString);
        run("pushInUnderflowSharesSkipZeroValuedProportionalShares", LineRepairCoverageTest.pushInUnderflowSharesSkipZeroValuedProportionalShares);
        run("withFillPushInGateAppliesOrReturnsTheSolution", LineRepairCoverageTest.withFillPushInGateAppliesOrReturnsTheSolution);
        TestTraceRecorder.flushClass("LineRepairCoverageTest");
        run("fillPullAcrossDifferentTechnicalSpansSkipsTierComparisons", LineRepairTailCoverageTest.fillPullAcrossDifferentTechnicalSpansSkipsTierComparisons);
        TestTraceRecorder.flushClass("LineRepairTailCoverageTest");
        run("westernDominantLineDoesNotStretchAroundCjkPunctuation", JustifierTest.westernDominantLineDoesNotStretchAroundCjkPunctuation);
        run("explicitInlineObjectBoundariesShareUniformStretchOnFormulaOnlyLine",
            JustifierTest.explicitInlineObjectBoundariesShareUniformStretchOnFormulaOnlyLine);
        run("formulaBoundariesStretchPunctuationThenRelationsThenBinaryOperators",
            JustifierTest.formulaBoundariesStretchPunctuationThenRelationsThenBinaryOperators);
        run("mixedCjkLineStillStretchesPunctuationWesternBoundary", JustifierTest.mixedCjkLineStillStretchesPunctuationWesternBoundary);
        run("typedSinoWesternSpaceStretchesInTierTwo", JustifierTest.typedSinoWesternSpaceStretchesInTierTwo);
        run("typedSinoWesternSpaceIsCappedAtHalfEm", JustifierTest.typedSinoWesternSpaceIsCappedAtHalfEm);
        run("finalUniformSpacingIncludesWordAndSinoWesternGapsOnceEach", JustifierTest.finalUniformSpacingIncludesWordAndSinoWesternGapsOnceEach);
        run("westernBracketsTouchingCjkShareTierThreeStretch", JustifierTest.westernBracketsTouchingCjkShareTierThreeStretch);
        run("attachedReferenceUsesTheVirtualProseBoundaryForStretching", JustifierTest.attachedReferenceUsesTheVirtualProseBoundaryForStretching);
        run("inseparableNumberSymbolBoundaryNeverStretches", JustifierTest.inseparableNumberSymbolBoundaryNeverStretches);
        run("fixedSinoWesternGapDoesNotJoinFinalUniformSpacing", JustifierTest.fixedSinoWesternGapDoesNotJoinFinalUniformSpacing);
        run("virtualSinoWesternStretchRequiresAlphaNumericBoundaryChar", JustifierTest.virtualSinoWesternStretchRequiresAlphaNumericBoundaryChar);
        run("typedSpaceBeforeSlashLedLatinRunIsNotSinoWesternGap", JustifierTest.typedSpaceBeforeSlashLedLatinRunIsNotSinoWesternGap);
        run("sinoWesternStretchRespectsThirdEmCapWhenStyleSetsIt", JustifierTest.sinoWesternStretchRespectsThirdEmCapWhenStyleSetsIt);
        TestTraceRecorder.flushClass("JustifierTest");
        run("attachedInlineVirtualAutoSpaceJoinsTierTwo", JustifierCoverageTest.attachedInlineVirtualAutoSpaceJoinsTierTwo);
        run("attachedInlineVirtualInterCharHonoursNoStretchProtection", JustifierCoverageTest.attachedInlineVirtualInterCharHonoursNoStretchProtection);
        run("attachedInlineVirtualSinoWesternNeedsStretchEnabled", JustifierCoverageTest.attachedInlineVirtualSinoWesternNeedsStretchEnabled);
        run("cjkLineWithNoOpportunitiesReportsUnfilledWithoutFallback", JustifierCoverageTest.cjkLineWithNoOpportunitiesReportsUnfilledWithoutFallback);
        run("compressDistributesTierByTier", JustifierCoverageTest.compressDistributesTierByTier);
        run("compressEarlyExitsAndFiltersDegenerateInputs", JustifierCoverageTest.compressEarlyExitsAndFiltersDegenerateInputs);
        run("emergencyTrackingFillsTheResidualForAuthorizedBoundaries", JustifierCoverageTest.emergencyTrackingFillsTheResidualForAuthorizedBoundaries);
        run("emptyClusterRangeDefersEveryTierLoop", JustifierCoverageTest.emptyClusterRangeDefersEveryTierLoop);
        run("misalignedRoleAndSpacingListsAreRejected", JustifierCoverageTest.misalignedRoleAndSpacingListsAreRejected);
        run("mixedCapacitySinoWesternOppsSkipZeroCapacityInOverflow", JustifierCoverageTest.mixedCapacitySinoWesternOppsSkipZeroCapacityInOverflow);
        run("paragraphEdgeSpaceLinesCoverTheBoundaryGuards", JustifierCoverageTest.paragraphEdgeSpaceLinesCoverTheBoundaryGuards);
        run("preferredInlineObjectKindsChainUntilFilled", JustifierCoverageTest.preferredInlineObjectKindsChainUntilFilled);
        run("preferredInlineObjectStretchRunsBySemanticKind", JustifierCoverageTest.preferredInlineObjectStretchRunsBySemanticKind);
        run("sinoWesternStretchDisabledSkipsTierTwoAndItsVirtualTracking", JustifierCoverageTest.sinoWesternStretchDisabledSkipsTierTwoAndItsVirtualTracking);
        run("skipKeepsTheDeficitAndRecordsTheReason", JustifierCoverageTest.skipKeepsTheDeficitAndRecordsTheReason);
        run("spaceGapProtectionCoversAllFourDisjuncts", JustifierCoverageTest.spaceGapProtectionCoversAllFourDisjuncts);
        run("technicalWhitespaceRequiresTheWhitespaceTierAndASourceSpace", JustifierCoverageTest.technicalWhitespaceRequiresTheWhitespaceTierAndASourceSpace);
        run("technicalWhitespaceStretchFillsAndStopsTheTierChain", JustifierCoverageTest.technicalWhitespaceStretchFillsAndStopsTheTierChain);
        run("typedSinoWesternSpaceNeedsBothEdgesToPair", JustifierCoverageTest.typedSinoWesternSpaceNeedsBothEdgesToPair);
        run("typedSinoWesternSpaceStretchesFromItsBase", JustifierCoverageTest.typedSinoWesternSpaceStretchesFromItsBase);
        run("uniformObjectBoundaryOpensTheGateAndFills", JustifierCoverageTest.uniformObjectBoundaryOpensTheGateAndFills);
        run("uniformTextBoundariesExcludeProtectedClasses", JustifierCoverageTest.uniformTextBoundariesExcludeProtectedClasses);
        run("virtualSinoWesternGapSkipsProtectedAndTypedEdges", JustifierCoverageTest.virtualSinoWesternGapSkipsProtectedAndTypedEdges);
        run("westernDominantLineStaysRagged", JustifierCoverageTest.westernDominantLineStaysRagged);
        run("wordSpaceAtTheCapOrCollapsedIsSkipped", JustifierCoverageTest.wordSpaceAtTheCapOrCollapsedIsSkipped);
        run("wordSpaceStretchesWithinItsCap", JustifierCoverageTest.wordSpaceStretchesWithinItsCap);
        run("zeroCapacitySinoWesternTierDefersEverythingDownward", JustifierCoverageTest.zeroCapacitySinoWesternTierDefersEverythingDownward);
        run("zeroDeficitReturnsAnEmptyPlanWithoutReason", JustifierCoverageTest.zeroDeficitReturnsAnEmptyPlanWithoutReason);
        run("zeroTechnicalStretchCapacityProducesNoOpportunity", JustifierCoverageTest.zeroTechnicalStretchCapacityProducesNoOpportunity);
        TestTraceRecorder.flushClass("JustifierCoverageTest");
        run("consumesTiersInAscendingOrder", JustifierCompressionTest.consumesTiersInAscendingOrder);
        run("nanSurplusEmitsNoAllocations", JustifierCompressionTest.nanSurplusEmitsNoAllocations);
        run("sharesEqualFractionWithinATier", JustifierCompressionTest.sharesEqualFractionWithinATier);
        run("reportsUnfilledWhenCapacityExhausted", JustifierCompressionTest.reportsUnfilledWhenCapacityExhausted);
        run("zeroSurplusIsNoOp", JustifierCompressionTest.zeroSurplusIsNoOp);
        TestTraceRecorder.flushClass("JustifierCompressionTest");
        run("attachedInlineVirtualSinoWesternBoundaryOutOfBounds", JustifierJfTest.attachedInlineVirtualSinoWesternBoundaryOutOfBounds);
        run("attachedInlineVirtualSinoWesternZeroHeadroomInAllocate", JustifierJfTest.attachedInlineVirtualSinoWesternZeroHeadroomInAllocate);
        run("cjkLatinMixedZeroAndPositiveCapacityAllocation", JustifierJfTest.cjkLatinMixedZeroAndPositiveCapacityAllocation);
        run("closedSpaceGapInTypedSinoWesternAndUniformSpace", JustifierJfTest.closedSpaceGapInTypedSinoWesternAndUniformSpace);
        run("closedSpaceGapInUniformSpaceWhenWordSpace", JustifierJfTest.closedSpaceGapInUniformSpaceWhenWordSpace);
        run("compressSubnormalUnderflowShrinkZero", JustifierJfTest.compressSubnormalUnderflowShrinkZero);
        run("compressionWithZeroSurplusAndZeroCapacity", JustifierJfTest.compressionWithZeroSurplusAndZeroCapacity);
        run("emptyLineClusterRangeSkipsUniformSpaceLoop", JustifierJfTest.emptyLineClusterRangeSkipsUniformSpaceLoop);
        run("preferredInlineObjectBoundaryOutOfBounds", JustifierJfTest.preferredInlineObjectBoundaryOutOfBounds);
        run("singleClusterRangeProducesNoOpportunities", JustifierJfTest.singleClusterRangeProducesNoOpportunities);
        run("typedSpaceAndWordSpacePredicateEdgeConditions", JustifierJfTest.typedSpaceAndWordSpacePredicateEdgeConditions);
        run("virtualNonSinoWesternBoundaryWhenAllowSinoWesternGapStretchIsFalse",
            JustifierJfTest.virtualNonSinoWesternBoundaryWhenAllowSinoWesternGapStretchIsFalse);
        run("virtualSinoWesternGapWhenAllowSinoWesternGapStretchIsFalse", JustifierJfTest.virtualSinoWesternGapWhenAllowSinoWesternGapStretchIsFalse);
        run("zeroCjkLatinHeadroomProducesNoOpportunities", JustifierJfTest.zeroCjkLatinHeadroomProducesNoOpportunities);
        TestTraceRecorder.flushClass("JustifierJfTest");
        run("resolveAttachedInlineVirtualBoundariesWithMultiplePrevious",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineVirtualBoundariesWithMultiplePrevious);
        run("resolveAttachedInlineVirtualBoundariesWithNoPrevious",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineVirtualBoundariesWithNoPrevious);
        run("resolveUnicodePunctuationBoundariesWithOpenPunctuation",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithOpenPunctuation);
        run("resolveUnicodePunctuationBoundariesWithPairedQuotes",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithPairedQuotes);
        run("resolveUnicodePunctuationBoundariesWithUnmatchedClosingPunctuation",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithUnmatchedClosingPunctuation);
        run("resolveUnicodePunctuationBoundariesWithCjkClosingAtLineStart",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithCjkClosingAtLineStart);
        run("resolveUnicodePunctuationBoundariesWithExclamationMark",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithExclamationMark);
        run("resolveUnicodePunctuationBoundariesWithInitialQuoteForbidLineEnd",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithInitialQuoteForbidLineEnd);
        run("resolveUnicodePunctuationBoundariesWithUnresolvedQuote",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithUnresolvedQuote);
        run("resolveUnicodePunctuationBoundariesWithMultipleClusters",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithMultipleClusters);
        run("resolveUnicodePunctuationBoundariesWithEmptyClusters",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithEmptyClusters);
        run("resolveUnicodePunctuationBoundariesWithAllCjkText",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithAllCjkText);
        run("resolveUnicodePunctuationBoundariesWithWesternClosingForbidLineStart",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithWesternClosingForbidLineStart);
        run("resolveUnicodePunctuationBoundariesWithCjkClosingForbidLineStart",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithCjkClosingForbidLineStart);
        run("resolveUnicodePunctuationBoundariesWithOpenPunctuationForbidLineEnd",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithOpenPunctuationForbidLineEnd);
        run("resolveUnicodePunctuationBoundariesWithPunctuationAndSpace",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithPunctuationAndSpace);
        run("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundary",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundary);
        run("resolveUnicodePunctuationBoundariesWithClosePunctuationClass",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithClosePunctuationClass);
        run("resolveUnicodePunctuationBoundariesWithInfixNumericSeparator",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithInfixNumericSeparator);
        run("resolveUnicodePunctuationBoundariesWithDecimalMarkAfterSpace",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithDecimalMarkAfterSpace);
        run("resolveUnicodePunctuationBoundariesWithRuleForLineStartInfix",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithRuleForLineStartInfix);
        run("resolveAttachedInlineInterCharBoundariesWithCjkBothCjk",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesWithCjkBothCjk);
        run("resolveAttachedInlineInterCharBoundariesWithWesternBracket",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesWithWesternBracket);
        run("resolveAttachedInlineInterCharBoundariesWithCjkBodyWesternBracket",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesWithCjkBodyWesternBracket);
        run("resolveAttachedInlineInterCharBoundariesRequiresMatchingClusterRoleEdgeSizes",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesRequiresMatchingClusterRoleEdgeSizes);
        run("resolveAttachedInlineInterCharBoundariesRequiresMatchingAttachmentSize",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesRequiresMatchingAttachmentSize);
        run("resolveAttachedInlineInterCharBoundariesPunctuationWesternNarrowTrailing",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesPunctuationWesternNarrowTrailing);
        run("resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsNull",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsNull);
        run("resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNotNarrow",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNotNarrow);
        run("resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowNotCjkPunct",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowNotCjkPunct);
        run("resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorNotDecimalMark",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorNotDecimalMark);
        run("resolveUnicodePunctuationBoundariesWithDecimalMarkAfterNonSpace",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithDecimalMarkAfterNonSpace);
        run("resolveUnicodePunctuationBoundariesWithQuoteDirectionFinal",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithQuoteDirectionFinal);
        run("resolveUnicodePunctuationBoundariesWithQuoteDirectionInitial",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithQuoteDirectionInitial);
        run("resolveUnicodePunctuationBoundariesWithQuoteDirectionUnresolved",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithQuoteDirectionUnresolved);
        run("resolveUnicodePunctuationBoundariesWithWordApostrophe2019",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithWordApostrophe2019);
        run("resolveUnicodePunctuationBoundariesWithLatinWordCodePoint",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithLatinWordCodePoint);
        run("resolveUnicodePunctuationBoundariesWithFirstSignificantCodePoint",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithFirstSignificantCodePoint);
        run("resolveUnicodePunctuationBoundariesWithLastSignificantCodePoint",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithLastSignificantCodePoint);
        run("resolveUnicodePunctuationBoundariesWithHasAuthoredBreak",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithHasAuthoredBreak);
        run("resolveUnicodePunctuationBoundariesWithNextContentCluster",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithNextContentCluster);
        run("resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasContent",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasContent);
        run("resolveUnicodePunctuationBoundariesWithClosePunctuation",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithClosePunctuation);
        run("resolveUnicodePunctuationBoundariesWithExclamationClass",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithExclamationClass);
        run("resolveUnicodePunctuationBoundariesWithCloseParenthesisClass",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithCloseParenthesisClass);
        run("resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorRule",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorRule);
        run("resolveUnicodePunctuationBoundariesWithRuleForLineStartElse",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithRuleForLineStartElse);
        run("resolveAttachedInlineInterCharBoundariesWithSinoWesternPair",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesWithSinoWesternPair);
        run("resolveUnicodePunctuationBoundariesWithCodePointBeforeSupplementary",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithCodePointBeforeSupplementary);
        run("resolveUnicodePunctuationBoundariesWithEmptyRange",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithEmptyRange);
        run("resolveUnicodePunctuationBoundariesWithFirstCodePointLength",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithFirstCodePointLength);
        run("resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePoint",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePoint);
        run("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryMandatory",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryMandatory);
        run("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryZWSP",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryZWSP);
        run("resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingInsideDigit",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingInsideDigit);
        run("resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingOutsideDigit",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingOutsideDigit);
        run("resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasAuthoredBreak",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasAuthoredBreak);
        run("resolveUnicodePunctuationBoundariesWithNextContentClusterHasAuthoredBreak",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithNextContentClusterHasAuthoredBreak);
        run("resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePointNonBmp",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePointNonBmp);
        run("resolveUnicodePunctuationBoundariesWithHasAuthoredBreakBoth",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithHasAuthoredBreakBoth);
        run("resolveAttachedInlineInterCharBoundariesWithBothCjkPunctuation",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesWithBothCjkPunctuation);
        run("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespace",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespace);
        run("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespaceThenNonWhitespace",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespaceThenNonWhitespace);
        run("resolveUnicodePunctuationBoundariesWithPreviousContentClusterEmpty",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithPreviousContentClusterEmpty);
        run("resolveUnicodePunctuationBoundariesWithNextContentClusterEmpty",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithNextContentClusterEmpty);
        run("resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSurrogate",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSurrogate);
        run("resolveUnicodePunctuationBoundariesWithHasAuthoredBreakMandatoryOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithHasAuthoredBreakMandatoryOnly);
        run("resolveUnicodePunctuationBoundariesWithCodePointBeforeSurrogatePair",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithCodePointBeforeSurrogatePair);
        run("resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSupplementary",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSupplementary);
        run("resolveAttachedInlineVirtualBoundariesAtStart", UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineVirtualBoundariesAtStart);
        run("resolveAttachedInlineInterCharBoundariesRequiresMatchingEdgesSize",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesRequiresMatchingEdgesSize);
        run("resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNotNarrow",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNotNarrow);
        run("resolveAttachedInlineInterCharBoundariesAllConditionsFalse",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesAllConditionsFalse);
        run("resolveAttachedInlineInterCharBoundariesNarrowNarrowPair",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesNarrowNarrowPair);
        run("resolveUnicodePunctuationBoundariesInfixNumericSeparatorWithSpaceAndNoSpace",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesInfixNumericSeparatorWithSpaceAndNoSpace);
        run("resolveUnicodePunctuationBoundariesDecimalMarkFollowingVariations",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesDecimalMarkFollowingVariations);
        run("resolveUnicodePunctuationBoundariesApostropheAndLatinWordBranches",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesApostropheAndLatinWordBranches);
        run("resolveUnicodePunctuationBoundariesSurrogateScanningVariations",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesSurrogateScanningVariations);
        run("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceIndexZero",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceIndexZero);
        run("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceNonWhitespacePrev",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceNonWhitespacePrev);
        run("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceEmptyPrev",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceEmptyPrev);
        run("resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryNonWhitespace",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryNonWhitespace);
        run("resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsContent",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsContent);
        run("resolveUnicodePunctuationBoundariesPreviousContentClusterEmptyOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesPreviousContentClusterEmptyOnly);
        run("resolveUnicodePunctuationBoundariesNextContentClusterReturnsContent",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesNextContentClusterReturnsContent);
        run("resolveUnicodePunctuationBoundariesHasAuthoredBreakWithCodePoint",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesHasAuthoredBreakWithCodePoint);
        run("resolveUnicodePunctuationBoundariesHasAuthoredBreakNullCodePoint",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesHasAuthoredBreakNullCodePoint);
        run("resolveUnicodePunctuationBoundariesFirstCodePointLengthBmp",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesFirstCodePointLengthBmp);
        run("resolveUnicodePunctuationBoundariesFirstCodePointLengthSurrogate",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesFirstCodePointLengthSurrogate);
        run("resolveUnicodePunctuationBoundariesCodePointAtOrNullSurrogatePair",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesCodePointAtOrNullSurrogatePair);
        run("resolveUnicodePunctuationBoundariesCodePointBeforeSurrogatePair",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesCodePointBeforeSurrogatePair);
        run("resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogate",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogate);
        run("resolveUnicodePunctuationBoundariesQuoteDirection2019SurrogateLeft",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesQuoteDirection2019SurrogateLeft);
        run("resolveUnicodePunctuationBoundariesPreviousContentClusterMultipleEmpty",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesPreviousContentClusterMultipleEmpty);
        run("resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryZWSPInMiddle",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryZWSPInMiddle);
        run("resolveUnicodePunctuationBoundariesLastSignificantCodePointSurrogateEnding",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesLastSignificantCodePointSurrogateEnding);
        run("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingInside",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingInside);
        run("resolveUnicodePunctuationBoundaryFullWidthCommaAfterSpaceStaysForbidden",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundaryFullWidthCommaAfterSpaceStaysForbidden);
        run("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingOutside",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingOutside);
        run("resolveUnicodePunctuationBoundariesQuoteDirection2019BmpLeft",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesQuoteDirection2019BmpLeft);
        run("resolveUnicodePunctuationBoundariesQuoteDirection2019RightWordOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesQuoteDirection2019RightWordOnly);
        run("resolveUnicodePunctuationBoundariesQuoteDirection2019LeftWordOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesQuoteDirection2019LeftWordOnly);
        run("resolveUnicodePunctuationBoundariesQuoteDirection2019NeitherWord",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesQuoteDirection2019NeitherWord);
        run("resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogateSingle",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogateSingle);
        run("resolveUnicodePunctuationBoundariesCodePointAtOrNullSupplementary",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesCodePointAtOrNullSupplementary);
        run("resolveUnicodePunctuationBoundariesHasAuthoredBreakEmptyString",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesHasAuthoredBreakEmptyString);
        run("resolveAttachedInlineInterCharBoundariesVirtualFromCjkPunctuationLeft",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesVirtualFromCjkPunctuationLeft);
        run("resolveUnicodePunctuationBoundariesDecimalMarkAtClusterZeroForbidden",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesDecimalMarkAtClusterZeroForbidden);
        run("resolveUnicodePunctuationBoundariesDecimalMarkAfterLetterClusterForbidden",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesDecimalMarkAfterLetterClusterForbidden);
        run("resolveUnicodePunctuationBoundariesDecimalMarkFollowedByLetterForbidden",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesDecimalMarkFollowedByLetterForbidden);
        run("resolveUnicodePunctuationBoundariesDecimalMarkAloneAfterSpaceForbidden",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesDecimalMarkAloneAfterSpaceForbidden);
        run("resolveUnicodePunctuationBoundariesAstralTailKeepsPairAsLastSignificant",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesAstralTailKeepsPairAsLastSignificant);
        run("resolveUnicodePunctuationBoundariesAuthoredBreakInsidePreviousClusterDropsUnbreakable",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesAuthoredBreakInsidePreviousClusterDropsUnbreakable);
        run("resolveUnicodePunctuationBoundariesApostropheAtTextStartNoLeftContext",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesApostropheAtTextStartNoLeftContext);
        run("resolveUnicodePunctuationBoundariesApostropheRightNeighbourUnpairedHighSurrogate",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesApostropheRightNeighbourUnpairedHighSurrogate);
        run("resolveUnicodePunctuationBoundariesApostropheLeftNeighbourSupplementaryPair",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesApostropheLeftNeighbourSupplementaryPair);
        run("resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNarrowOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNarrowOnly);
        run("resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowOnly);
        run("resolveAttachedInlineInterCharBoundariesSinoWesternOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesSinoWesternOnly);
        run("resolveAttachedInlineInterCharBoundariesWesternBracketOnly",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveAttachedInlineInterCharBoundariesWesternBracketOnly);
        run("resolveUnicodePunctuationBoundariesDecimalMarkAfterEmptyClusterForbidden",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesDecimalMarkAfterEmptyClusterForbidden);
        run("resolveUnicodePunctuationBoundariesApostropheRightNeighbourSupplementaryPair",
            UnicodePunctuationBoundaryResolverCoverageTest.resolveUnicodePunctuationBoundariesApostropheRightNeighbourSupplementaryPair);
        TestTraceRecorder.flushClass("UnicodePunctuationBoundaryResolverCoverageTest");
        run("clusterWiderThanMaxWidthGetsOwnLineRatherThanInfiniteLoop", GreedyLineBreakerTest.clusterWiderThanMaxWidthGetsOwnLineRatherThanInfiniteLoop);
        run("customKinsokuRuleOverridesDefault", GreedyLineBreakerTest.customKinsokuRuleOverridesDefault);
        run("doesNotHangWhenDisabled", GreedyLineBreakerTest.doesNotHangWhenDisabled);
        run("emptyInputProducesNoLines", GreedyLineBreakerTest.emptyInputProducesNoLines);
        run("fillsLineUntilOverflowThenStartsNewLine", GreedyLineBreakerTest.fillsLineUntilOverflowThenStartsNewLine);
        run("hangsPauseStopPastMeasureWhenEnabledAndPushInCannotFit", GreedyLineBreakerTest.hangsPauseStopPastMeasureWhenEnabledAndPushInCannotFit);
        run("keepsOpenerAtLineEndWhenItIsTheLineSoleCluster", GreedyLineBreakerTest.keepsOpenerAtLineEndWhenItIsTheLineSoleCluster);
        run("kinsokuCarriesPreviousWhenPushInCapacityCannotCoverOverflow", GreedyLineBreakerTest.kinsokuCarriesPreviousWhenPushInCapacityCannotCoverOverflow);
        run("kinsokuCarryPreviousMovesPrevClusterToNextLine", GreedyLineBreakerTest.kinsokuCarryPreviousMovesPrevClusterToNextLine);
        run("kinsokuLeaveRaggedWhenPrevLineIsSingleCluster", GreedyLineBreakerTest.kinsokuLeaveRaggedWhenPrevLineIsSingleCluster);
        run("kinsokuPushesForbiddenPunctuationIntoPreviousLineWhenGlueCapacityCoversOverflow",
            GreedyLineBreakerTest.kinsokuPushesForbiddenPunctuationIntoPreviousLineWhenGlueCapacityCoversOverflow);
        run("kinsokuRejectsCarryPreviousWhenCarriedLineWouldOverflow", GreedyLineBreakerTest.kinsokuRejectsCarryPreviousWhenCarriedLineWouldOverflow);
        run("mandatoryBreakBlocksKinsokuRepairAcrossBoundary", GreedyLineBreakerTest.mandatoryBreakBlocksKinsokuRepairAcrossBoundary);
        run("mandatoryBreakClosesLineAndPreservesTrailingEmptyLine", GreedyLineBreakerTest.mandatoryBreakClosesLineAndPreservesTrailingEmptyLine);
        run("misalignedClusterListsThrow", GreedyLineBreakerTest.misalignedClusterListsThrow);
        run("naturalAndAdjustedWidthsTrackIndependently", GreedyLineBreakerTest.naturalAndAdjustedWidthsTrackIndependently);
        run("pushInStillPreferredOverHangWhenGlueCovers", GreedyLineBreakerTest.pushInStillPreferredOverHangWhenGlueCovers);
        run("retreatsBreakSoLineDoesNotEndOnOpeningMark", GreedyLineBreakerTest.retreatsBreakSoLineDoesNotEndOnOpeningMark);
        run("singleClusterFitsOnOneLine", GreedyLineBreakerTest.singleClusterFitsOnOneLine);
        TestTraceRecorder.flushClass("GreedyLineBreakerTest");

        run("hangingTailIsExcludedFromFillDensityGeometry", LookaheadLineBreakerTest.hangingTailIsExcludedFromFillDensityGeometry);
        run("hangingClustersMustBeAContiguousTrailingSuffix", LookaheadLineBreakerTest.hangingClustersMustBeAContiguousTrailingSuffix);
        run("compatibilityHangingIndexSkipsATrailingMandatoryBreakControl",
            LookaheadLineBreakerTest.compatibilityHangingIndexSkipsATrailingMandatoryBreakControl);
        run("emptyInputProducesNoLines", LookaheadLineBreakerTest.emptyInputProducesNoLines);
        run("lookaheadMatchesGreedyWhenShiftingEarlierGivesNoBenefit", LookaheadLineBreakerTest.lookaheadMatchesGreedyWhenShiftingEarlierGivesNoBenefit);
        run("lookaheadShiftsBreakEarlierToAvoidKinsokuRepair", LookaheadLineBreakerTest.lookaheadShiftsBreakEarlierToAvoidKinsokuRepair);
        run("lookaheadKeepsGreedyBreakWhenPushInGlueCoversRepair", LookaheadLineBreakerTest.lookaheadKeepsGreedyBreakWhenPushInGlueCoversRepair);
        run("lookaheadScoresFuturePushInBeforeChoosingEarlierBreak", LookaheadLineBreakerTest.lookaheadScoresFuturePushInBeforeChoosingEarlierBreak);
        run("lookaheadFallsBackToGreedyWhenAlternativesAreWorse", LookaheadLineBreakerTest.lookaheadFallsBackToGreedyWhenAlternativesAreWorse);
        run("lookaheadAvoidsConsecutiveSyntheticHyphenBreaks", LookaheadLineBreakerTest.lookaheadAvoidsConsecutiveSyntheticHyphenBreaks);
        run("lookaheadScoresKinsokuRepairsWithUnbreakableRanges", LookaheadLineBreakerTest.lookaheadScoresKinsokuRepairsWithUnbreakableRanges);
        run("windowZeroReducesLookaheadToGreedy", LookaheadLineBreakerTest.windowZeroReducesLookaheadToGreedy);
        TestTraceRecorder.flushClass("LookaheadLineBreakerTest");
        run("testLineBreakerStrategyNameDefault", LineBreakerCoverage2Test.testLineBreakerStrategyNameDefault);
        run("testLookaheadLineBreakerPreconditions", LineBreakerCoverage2Test.testLookaheadLineBreakerPreconditions);
        run("testLookaheadCandidateFilteringWithNonRenderingControlClusters",
            LineBreakerCoverage2Test.testLookaheadCandidateFilteringWithNonRenderingControlClusters);
        run("testLookaheadHardBreakAtEndAndMiddle", LineBreakerCoverage2Test.testLookaheadHardBreakAtEndAndMiddle);
        run("testLineCandidateEndsWithProgressiveBreak", LineBreakerCoverage2Test.testLineCandidateEndsWithProgressiveBreak);
        run("testLineGapCount", LineBreakerCoverage2Test.testLineGapCount);
        run("testRebuildLineEmptyRangeThrows", LineBreakerCoverage2Test.testRebuildLineEmptyRangeThrows);
        run("testFindGreedyEndDefaultArgs", LineBreakerCoverage2Test.testFindGreedyEndDefaultArgs);
        run("testLookaheadOrphanAndSyntheticHyphenRuns", LineBreakerCoverage2Test.testLookaheadOrphanAndSyntheticHyphenRuns);
        TestTraceRecorder.flushClass("LineBreakerCoverage2Test");

        run("attachedAsciiPointMarkKinsokuProtectsRuns", PunctuationGeometryStageCoverageTest.attachedAsciiPointMarkKinsokuProtectsRuns);
        run("attachedAsciiPointMarkKinsokuRejectsDetachedRuns", PunctuationGeometryStageCoverageTest.attachedAsciiPointMarkKinsokuRejectsDetachedRuns);
        run("attachedAsciiPointMarksNeedAContiguousNonSpaceBase", PunctuationGeometryStageCoverageTest.attachedAsciiPointMarksNeedAContiguousNonSpaceBase);
        run("attachedMarksAcceptAsciiPointMarksAfterObjects", PunctuationGeometryStageCoverageTest.attachedMarksAcceptAsciiPointMarksAfterObjects);
        run("attachedMarksCollapseSeparatorSpaceBeforeTheMark", PunctuationGeometryStageCoverageTest.attachedMarksCollapseSeparatorSpaceBeforeTheMark);
        run("attachedMarksRejectMissingObjectsAndGappedRanges", PunctuationGeometryStageCoverageTest.attachedMarksRejectMissingObjectsAndGappedRanges);
        run("attachedRunsOwnOneVirtualGapAtTheirTrailingEdge", PunctuationGeometryStageCoverageTest.attachedRunsOwnOneVirtualGapAtTheirTrailingEdge);
        run("emptyDisplayTextProducesNoAtoms", PunctuationGeometryStageCoverageTest.emptyDisplayTextProducesNoAtoms);
        run("glyphlessClustersUseThePurePolicyPath", PunctuationGeometryStageCoverageTest.glyphlessClustersUseThePurePolicyPath);
        run("inlineBoxSpansAddStructuralEdgesAndSkipDegenerateRanges",
            PunctuationGeometryStageCoverageTest.inlineBoxSpansAddStructuralEdgesAndSkipDegenerateRanges);
        run("inlineObjectKinsokuProtectsOrHangsAttachedMarks", PunctuationGeometryStageCoverageTest.inlineObjectKinsokuProtectsOrHangsAttachedMarks);
        run("multipleGlyphsForOneCharacterUnionIntoASingleInkBox", PunctuationGeometryStageCoverageTest.multipleGlyphsForOneCharacterUnionIntoASingleInkBox);
        run("narrowInlineBoxesOwnTheirOuterAutoSpace", PunctuationGeometryStageCoverageTest.narrowInlineBoxesOwnTheirOuterAutoSpace);
        run("perCharacterInkSubtractsPrecedingGlyphPens", PunctuationGeometryStageCoverageTest.perCharacterInkSubtractsPrecedingGlyphPens);
        run("spaceReplacementSkipsDisabledModeNullBoundariesAndExactWidths",
            PunctuationGeometryStageCoverageTest.spaceReplacementSkipsDisabledModeNullBoundariesAndExactWidths);
        run("spacingBoundariesCountEachWideNarrowGapOnce", PunctuationGeometryStageCoverageTest.spacingBoundariesCountEachWideNarrowGapOnce);
        run("typedSpaceBetweenWideAndNarrowIsReplacedByTheGap", PunctuationGeometryStageCoverageTest.typedSpaceBetweenWideAndNarrowIsReplacedByTheGap);
        run("unionWithoutBoundsFallsBackToTheFirstGlyph", PunctuationGeometryStageCoverageTest.unionWithoutBoundsFallsBackToTheFirstGlyph);
        run("unmatchedGlyphCountsRecordTheAmbiguousFallback", PunctuationGeometryStageCoverageTest.unmatchedGlyphCountsRecordTheAmbiguousFallback);
        run("virtualGapsRespectNarrowToWideEdgesAndTheirNeighbours",
            PunctuationGeometryStageCoverageTest.virtualGapsRespectNarrowToWideEdgesAndTheirNeighbours);
        run("wideToNarrowBoundariesInsertLeadingAndTrailingGaps", PunctuationGeometryStageCoverageTest.wideToNarrowBoundariesInsertLeadingAndTrailingGaps);
        TestTraceRecorder.flushClass("PunctuationGeometryStageCoverageTest");
        run("compressedSameTierBoundaryIsNotReportedAsPromotion", ParagraphDpLineBreakerTest.compressedSameTierBoundaryIsNotReportedAsPromotion);
        run("tilesAllClustersInOrder", ParagraphDpLineBreakerTest.tilesAllClustersInOrder);
        run("singleLineWhenEverythingFits", ParagraphDpLineBreakerTest.singleLineWhenEverythingFits);
        run("mandatoryBreakBindsControlToPreviousLine", ParagraphDpLineBreakerTest.mandatoryBreakBindsControlToPreviousLine);
        run("trailingMandatoryBreakEmitsParagraphEndLine", ParagraphDpLineBreakerTest.trailingMandatoryBreakEmitsParagraphEndLine);
        run("neverBreaksInsideUnbreakableRange", ParagraphDpLineBreakerTest.neverBreaksInsideUnbreakableRange);
        run("kinsokuAvoidanceRoutesAroundForbiddenLineStart", ParagraphDpLineBreakerTest.kinsokuAvoidanceRoutesAroundForbiddenLineStart);
        run("compressionEdgeRecordsPushInRepair", ParagraphDpLineBreakerTest.compressionEdgeRecordsPushInRepair);
        run("compressionDisabledWithoutPushInFlag", ParagraphDpLineBreakerTest.compressionDisabledWithoutPushInFlag);
        run("overWideSingleClusterStillProgresses", ParagraphDpLineBreakerTest.overWideSingleClusterStillProgresses);
        TestTraceRecorder.flushClass("ParagraphDpLineBreakerTest");
        run("emptyClustersReturnAnEmptySolution", ParagraphDpLineBreakerCoverageTest.emptyClustersReturnAnEmptySolution);
        run("mismatchedNaturalAndAdjustedSizesAreRejected", ParagraphDpLineBreakerCoverageTest.mismatchedNaturalAndAdjustedSizesAreRejected);
        run("negativeCandidateWindowIsRejected", ParagraphDpLineBreakerCoverageTest.negativeCandidateWindowIsRejected);
        run("shrinkPrefixSkipsNonPositiveAndOutOfRangeOpportunities",
            ParagraphDpLineBreakerCoverageTest.shrinkPrefixSkipsNonPositiveAndOutOfRangeOpportunities);
        run("lineEndOnlyCapacityFeedsTheCompressedEdgeAtTheLineEnd", ParagraphDpLineBreakerCoverageTest.lineEndOnlyCapacityFeedsTheCompressedEdgeAtTheLineEnd);
        run("compressedEndsMayReachTheSegmentEnd", ParagraphDpLineBreakerCoverageTest.compressedEndsMayReachTheSegmentEnd);
        run("compressedFinalMandatoryLineUsesTheCompressedCommitBranch",
            ParagraphDpLineBreakerCoverageTest.compressedFinalMandatoryLineUsesTheCompressedCommitBranch);
        run("tierPromotionRoutesTheRepairReasonThroughThePromotionCode",
            ParagraphDpLineBreakerCoverageTest.tierPromotionRoutesTheRepairReasonThroughThePromotionCode);
        run("promotionCheckReturnsFalseWhenTheCandidateEndHasNoOpportunity",
            ParagraphDpLineBreakerCoverageTest.promotionCheckReturnsFalseWhenTheCandidateEndHasNoOpportunity);
        run("mandatorySegmentFiltersTheControlBoundaryFromCandidates",
            ParagraphDpLineBreakerCoverageTest.mandatorySegmentFiltersTheControlBoundaryFromCandidates);
        run("narrowWindowsDropEndsAtOrBelowTheLineStart", ParagraphDpLineBreakerCoverageTest.narrowWindowsDropEndsAtOrBelowTheLineStart);
        run("interfaceDefaultStrategyNameIsCustom", ParagraphDpLineBreakerCoverageTest.interfaceDefaultStrategyNameIsCustom);
        TestTraceRecorder.flushClass("ParagraphDpLineBreakerCoverageTest");
        run("testShrinkOpportunitiesNegativeAndOutOfRange", ParagraphDpLineBreakerCoverage2Test.testShrinkOpportunitiesNegativeAndOutOfRange);
        run("testCandidateWindowBoundsCompressionEdges", ParagraphDpLineBreakerCoverage2Test.testCandidateWindowBoundsCompressionEdges);
        run("testProgressiveTierPromotionBranches", ParagraphDpLineBreakerCoverage2Test.testProgressiveTierPromotionBranches);
        run("testCommitSegmentOriginalBreakNotNullResultingBreakNull",
            ParagraphDpLineBreakerCoverage2Test.testCommitSegmentOriginalBreakNotNullResultingBreakNull);
        run("testTierPreferredPoolEmptyFallback", ParagraphDpLineBreakerCoverage2Test.testTierPreferredPoolEmptyFallback);
        run("testHardBreakAfterClustersInDpCommit", ParagraphDpLineBreakerCoverage2Test.testHardBreakAfterClustersInDpCommit);
        run("testCandidateEndsWindowBelowLineStart", ParagraphDpLineBreakerCoverage2Test.testCandidateEndsWindowBelowLineStart);
        TestTraceRecorder.flushClass("ParagraphDpLineBreakerCoverage2Test");
        run("zeroValuesSerializeWithoutSign", PreparedParagraphJsonNumberTest.zeroValuesSerializeWithoutSign);
        run("integerFormsPadToDecimalExponent", PreparedParagraphJsonNumberTest.integerFormsPadToDecimalExponent);
        run("fractionFormsInsertDecimalPoint", PreparedParagraphJsonNumberTest.fractionFormsInsertDecimalPoint);
        run("smallFractionsUseLeadingZeros", PreparedParagraphJsonNumberTest.smallFractionsUseLeadingZeros);
        run("exponentFormsCarryExplicitSign", PreparedParagraphJsonNumberTest.exponentFormsCarryExplicitSign);
        run("negativeValuesKeepOnlyMagnitudeSign", PreparedParagraphJsonNumberTest.negativeValuesKeepOnlyMagnitudeSign);
        run("exactTiesRoundToEvenDigit", PreparedParagraphJsonNumberTest.exactTiesRoundToEvenDigit);
        run("exactExpansionRoundsPlatformDigits", PreparedParagraphJsonNumberTest.exactExpansionRoundsPlatformDigits);
        run("boundaryMidpointsAcceptOnlyAtEvenMantissa", PreparedParagraphJsonNumberTest.boundaryMidpointsAcceptOnlyAtEvenMantissa);
        run("decimalAlignedMantissaSkipsZeroChunk", PreparedParagraphJsonNumberTest.decimalAlignedMantissaSkipsZeroChunk);
        run("subnormalExpansionsSerialize", PreparedParagraphJsonNumberTest.subnormalExpansionsSerialize);
        TestTraceRecorder.flushClass("PreparedParagraphJsonNumberTest");
        run("contentWithoutInlineBoxesOmitsInlineEdgesArray", PreparedParagraphInlineEdgesTest.contentWithoutInlineBoxesOmitsInlineEdgesArray);
        run("endOnlyInlineBoxEmitsEdgeWithoutInlineStartField", PreparedParagraphInlineEdgesTest.endOnlyInlineBoxEmitsEdgeWithoutInlineStartField);
        TestTraceRecorder.flushClass("PreparedParagraphInlineEdgesTest");
        run("rubyBaseRangeCrossingClusterBoundariesDropsOutOfPerLineExtents",
            org.tiqian.layout.LineGeometryDirectTailTest.rubyBaseRangeCrossingClusterBoundariesDropsOutOfPerLineExtents);
        run("rubiesOnBothLinesExerciseBothSidesOfTheOverlapTest",
            org.tiqian.layout.LineGeometryDirectTailTest.rubiesOnBothLinesExerciseBothSidesOfTheOverlapTest);
        run("emptyLineSolutionYieldsZeroArraysAndZeroMaxExtra", org.tiqian.layout.LineGeometryDirectTailTest.emptyLineSolutionYieldsZeroArraysAndZeroMaxExtra);
        run("hangingBelowLineRangeIsRejected", org.tiqian.layout.LineCandidateValidationTest.hangingBelowLineRangeIsRejected);
        run("hangingEntirelyAboveLineIsRejected", org.tiqian.layout.LineCandidateValidationTest.hangingEntirelyAboveLineIsRejected);
        run("hangingAboveLineLastIsRejected", org.tiqian.layout.LineCandidateValidationTest.hangingAboveLineLastIsRejected);
        run("nonContiguousHangingIsRejected", org.tiqian.layout.LineCandidateValidationTest.nonContiguousHangingIsRejected);
        run("inMeasureRangeExcludesHangingSuffix", org.tiqian.layout.LineCandidateValidationTest.inMeasureRangeExcludesHangingSuffix);
        run("inMeasureRangeIsFullLineWithoutHanging", org.tiqian.layout.LineCandidateValidationTest.inMeasureRangeIsFullLineWithoutHanging);
        run("objectTopIntrusionBelowRubyDemandKeepsBoundaryClearanceZero",
            org.tiqian.layout.LineGeometryDirectTailTest.objectTopIntrusionBelowRubyDemandKeepsBoundaryClearanceZero);
        run("objectTopIntrusionDominatingRubyDemandAddsBoundaryClearance",
            org.tiqian.layout.LineGeometryDirectTailTest.objectTopIntrusionDominatingRubyDemandAddsBoundaryClearance);
        run("objectFlushWithBaseTopSkipsIntrusionConjunctionEarly",
            org.tiqian.layout.LineGeometryDirectTailTest.objectFlushWithBaseTopSkipsIntrusionConjunctionEarly);
        run("metricListWithoutIdeographicEmBoxFallsBackToAllClusters",
            org.tiqian.layout.LineGeometryDirectTailTest.metricListWithoutIdeographicEmBoxFallsBackToAllClusters);
        run("emptyMetricListTakesEmptyParagraphBaselineFallback",
            org.tiqian.layout.LineGeometryDirectTailTest.emptyMetricListTakesEmptyParagraphBaselineFallback);
        TestTraceRecorder.flushClass("LineGeometryDirectTailTest");
        run("budgetsResolveAdvancesThroughRemainingGlue", PunctuationGeometryLedgerCoverageTest.budgetsResolveAdvancesThroughRemainingGlue);
        run("glueCapacitiesReportSidesAndPairing", PunctuationGeometryLedgerCoverageTest.glueCapacitiesReportSidesAndPairing);
        run("sideConsumptionIsCappedAndSkipsNonPositiveAmounts", PunctuationGeometryLedgerCoverageTest.sideConsumptionIsCappedAndSkipsNonPositiveAmounts);
        run("justificationDeltasAndStructuralChannelsFeedResolvedAdvance",
            PunctuationGeometryLedgerCoverageTest.justificationDeltasAndStructuralChannelsFeedResolvedAdvance);
        run("geometryWithoutBudgetFallsBackToBodyWidth", PunctuationGeometryLedgerCoverageTest.geometryWithoutBudgetFallsBackToBodyWidth);
        run("decisionInfoListsEveryGeometryWithBudgets", PunctuationGeometryLedgerCoverageTest.decisionInfoListsEveryGeometryWithBudgets);
        run("spacingPlanAdjustmentsConsumeByTargetAndAnchor", PunctuationGeometryLedgerCoverageTest.spacingPlanAdjustmentsConsumeByTargetAndAnchor);
        run("attachedInlineBoundariesRequireAlignmentAndRunOnlyWithAttachments",
            PunctuationGeometryLedgerCoverageTest.attachedInlineBoundariesRequireAlignmentAndRunOnlyWithAttachments);
        run("attachedInlineBoundaryAtLineEndConsumesTrailingGlue", PunctuationGeometryLedgerCoverageTest.attachedInlineBoundaryAtLineEndConsumesTrailingGlue);
        run("attachedInlineBoundaryAdjacentPunctuationHalvesTheVirtualGlue",
            PunctuationGeometryLedgerCoverageTest.attachedInlineBoundaryAdjacentPunctuationHalvesTheVirtualGlue);
        run("attachedInlineBoundaryBeforeAsciiPointMarkCollapsesLikeAdjacent",
            PunctuationGeometryLedgerCoverageTest.attachedInlineBoundaryBeforeAsciiPointMarkCollapsesLikeAdjacent);
        run("attachedInlineBoundarySkipsMandatoryBreakNeighbour", PunctuationGeometryLedgerCoverageTest.attachedInlineBoundarySkipsMandatoryBreakNeighbour);
        run("attachedInlineBoundaryWithoutGlueEmitsNoDecision", PunctuationGeometryLedgerCoverageTest.attachedInlineBoundaryWithoutGlueEmitsNoDecision);
        run("lineEdgeTrimConsumesHalfWidthAtEdgesAndSkipsEmptyInputs",
            PunctuationGeometryLedgerCoverageTest.lineEdgeTrimConsumesHalfWidthAtEdgesAndSkipsEmptyInputs);
        run("lineEdgeTrimConsumesCentredPunctuationOncePerLine", PunctuationGeometryLedgerCoverageTest.lineEdgeTrimConsumesCentredPunctuationOncePerLine);
        run("clusterIndexRangeFindCoveredClusters", PunctuationGeometryLedgerCoverageTest.clusterIndexRangeFindCoveredClusters);
        TestTraceRecorder.flushClass("PunctuationGeometryLedgerCoverageTest");
        TestTraceRecorder.flushClass("LineCandidateValidationTest");
        run("sourceWhitespaceCapacityKeepsStructuralTierAheadOfSyllable",
            org.tiqian.layout.ProgressiveTechnicalBreakTest.sourceWhitespaceCapacityKeepsStructuralTierAheadOfSyllable);
        run("lookaheadMayNotReplaceSelectedEmergencyBoundaryWithEarlierSameTierCut",
            org.tiqian.layout.ProgressiveTechnicalBreakTest.lookaheadMayNotReplaceSelectedEmergencyBoundaryWithEarlierSameTierCut);
        run("foreignSpanCandidateSurvivesThePromotionPoolPurge",
            org.tiqian.layout.ParagraphDpTierPromotionPoolTest.foreignSpanCandidateSurvivesThePromotionPoolPurge);
        run("committedCompressedLineWithForeignSpanOpportunitiesKeepsPlainPushInReason",
            org.tiqian.layout.ParagraphDpTierPromotionPoolTest.committedCompressedLineWithForeignSpanOpportunitiesKeepsPlainPushInReason);
        run("committedCompressedEndWithoutOpportunityKeepsPlainPushInReason",
            org.tiqian.layout.ParagraphDpTierPromotionPoolTest.committedCompressedEndWithoutOpportunityKeepsPlainPushInReason);
        run("carryPreviousRefusesToSplitUnbreakableSpan", org.tiqian.layout.PushInLineWideCapacityTest.carryPreviousRefusesToSplitUnbreakableSpan);
        run("pushInAggregatesShrinkFromMultiplePrecedingClusters",
            org.tiqian.layout.PushInLineWideCapacityTest.pushInAggregatesShrinkFromMultiplePrecedingClusters);
        run("pushInMergesOffenderThatFitsAfterChainedRepairs", org.tiqian.layout.PushInLineWideCapacityTest.pushInMergesOffenderThatFitsAfterChainedRepairs);
        run("pushInOffenderOnlyCapacityStillWorksBackCompat", org.tiqian.layout.PushInLineWideCapacityTest.pushInOffenderOnlyCapacityStillWorksBackCompat);
        run("pushInRejectsWhenLineWideCapacityStillInsufficient",
            org.tiqian.layout.PushInLineWideCapacityTest.pushInRejectsWhenLineWideCapacityStillInsufficient);
        TestTraceRecorder.flushClass("ProgressiveTechnicalBreakTest");
        TestTraceRecorder.flushClass("ParagraphDpTierPromotionPoolTest");
        TestTraceRecorder.flushClass("PushInLineWideCapacityTest");
        run("dashShapingDecisionWithGlyphIds", org.tiqian.layout.PreparedParagraphJfTest.dashShapingDecisionWithGlyphIds);
        run("ecmaJsonNumberEdgeCases", org.tiqian.layout.PreparedParagraphJfTest.ecmaJsonNumberEdgeCases);
        run("inlineBoxEdgesAndEmphasisDotsFilter", org.tiqian.layout.PreparedParagraphJfTest.inlineBoxEdgesAndEmphasisDotsFilter);
        run("styleAtAndStyleDeltasInPreparedParagraphJson", org.tiqian.layout.PreparedParagraphJfTest.styleAtAndStyleDeltasInPreparedParagraphJson);
        TestTraceRecorder.flushClass("PreparedParagraphJfTest");
        run("dashClusterEmitsShapingEvidenceBlock", org.tiqian.layout.PreparedParagraphPlanConstructionTest.dashClusterEmitsShapingEvidenceBlock);
        run("inlineObjectCellEmitsAdvanceOverride", org.tiqian.layout.PreparedParagraphPlanConstructionTest.inlineObjectCellEmitsAdvanceOverride);
        run("jsonStringEscapesQuotesBackslashesAndControlCharacters",
            org.tiqian.layout.PreparedParagraphPlanConstructionTest.jsonStringEscapesQuotesBackslashesAndControlCharacters);
        run("multiUnitClusterMarksShapingBoundary", org.tiqian.layout.PreparedParagraphPlanConstructionTest.multiUnitClusterMarksShapingBoundary);
        run("negativeZeroAndExponentWidthsNormalize", org.tiqian.layout.PreparedParagraphPlanConstructionTest.negativeZeroAndExponentWidthsNormalize);
        run("openTypeFeaturesAndRenderFontFamilyAttachPerCluster",
            org.tiqian.layout.PreparedParagraphPlanConstructionTest.openTypeFeaturesAndRenderFontFamilyAttachPerCluster);
        run("paragraphEvidenceEmitsEverySection", org.tiqian.layout.PreparedParagraphPlanConstructionTest.paragraphEvidenceEmitsEverySection);
        run("planWithDiagnosticsListsCapabilityIssuesAndAdvanceSuspects",
            org.tiqian.layout.PreparedParagraphPlanConstructionTest.planWithDiagnosticsListsCapabilityIssuesAndAdvanceSuspects);
        run("punctuationInkFloorAndLatinRoleMarkCells", org.tiqian.layout.PreparedParagraphPlanConstructionTest.punctuationInkFloorAndLatinRoleMarkCells);
        run("styleDeltaListsOnlyPaintFields", org.tiqian.layout.PreparedParagraphPlanConstructionTest.styleDeltaListsOnlyPaintFields);
        run("zeroWidthBreakClusterSurvivesEmptyDisplayText",
            org.tiqian.layout.PreparedParagraphPlanConstructionTest.zeroWidthBreakClusterSurvivesEmptyDisplayText);
        TestTraceRecorder.flushClass("PreparedParagraphPlanConstructionTest");

        run("closingPlusClosingCollapsesInnerToZero", PunctuationSpacingRuleTest.closingPlusClosingCollapsesInnerToZero);
        run("openingPlusOpeningCollapsesInnerToZero", PunctuationSpacingRuleTest.openingPlusOpeningCollapsesInnerToZero);
        run("closingPlusOpeningKeepsHalfEmGap", PunctuationSpacingRuleTest.closingPlusOpeningKeepsHalfEmGap);
        run("pauseStopPlusOpeningCollapsesByHalfEm", PunctuationSpacingRuleTest.pauseStopPlusOpeningCollapsesByHalfEm);
        run("consecutivePauseOrStopMarksCompressLikeAnyAdjacentPair", PunctuationSpacingRuleTest.consecutivePauseOrStopMarksCompressLikeAnyAdjacentPair);
        run("closingPlusPauseOrStopStillCompresses", PunctuationSpacingRuleTest.closingPlusPauseOrStopStillCompresses);
        run("nonAdjacentPunctuationAtomsAreNotCompressed", PunctuationSpacingRuleTest.nonAdjacentPunctuationAtomsAreNotCompressed);
        run("cjkClosingBeforeAsciiPointMarkConsumesOnlyClosingGlue", PunctuationSpacingRuleTest.cjkClosingBeforeAsciiPointMarkConsumesOnlyClosingGlue);
        run("cjkClosingDoesNotCompressAcrossWhitespaceBeforeAsciiPointMark",
            PunctuationSpacingRuleTest.cjkClosingDoesNotCompressAcrossWhitespaceBeforeAsciiPointMark);
        TestTraceRecorder.flushClass("PunctuationSpacingRuleTest");
        run("asciiPointMarkKinsokuSkipsEmptyTextClusters", PunctuationGeometryBranchArmsCoverageTest.asciiPointMarkKinsokuSkipsEmptyTextClusters);
        run("attachedAsciiPointMarkCheckSkipsEmptyPreviousText", PunctuationGeometryBranchArmsCoverageTest.attachedAsciiPointMarkCheckSkipsEmptyPreviousText);
        run("attachedBoundaryReasonFallsBackToNaturalWithoutLeftAtom",
            PunctuationGeometryBranchArmsCoverageTest.attachedBoundaryReasonFallsBackToNaturalWithoutLeftAtom);
        run("attachedBoundaryRecordsNullCharactersForEmptyTextClusters",
            PunctuationGeometryBranchArmsCoverageTest.attachedBoundaryRecordsNullCharactersForEmptyTextClusters);
        run("attachedBoundaryWithPlainPreviousClusterKeepsTheRightBudget",
            PunctuationGeometryBranchArmsCoverageTest.attachedBoundaryWithPlainPreviousClusterKeepsTheRightBudget);
        run("attachedMarkWalkStopsMidRunAtAGap", PunctuationGeometryBranchArmsCoverageTest.attachedMarkWalkStopsMidRunAtAGap);
        run("attachedRunAtParagraphEndEmitsNoAutoSpace", PunctuationGeometryBranchArmsCoverageTest.attachedRunAtParagraphEndEmitsNoAutoSpace);
        run("attachedTrailingGlueWidensABudgetedEndCluster", PunctuationGeometryBranchArmsCoverageTest.attachedTrailingGlueWidensABudgetedEndCluster);
        run("centredAdjacencyConsumesBothSidesEqually", PunctuationGeometryBranchArmsCoverageTest.centredAdjacencyConsumesBothSidesEqually);
        run("emptyTextClustersCannotBeAttachedMarks", PunctuationGeometryBranchArmsCoverageTest.emptyTextClustersCannotBeAttachedMarks);
        run("glueCapacitiesMarkCentredFramesAsPaired", PunctuationGeometryBranchArmsCoverageTest.glueCapacitiesMarkCentredFramesAsPaired);
        run("haltAdvanceIsRejectedAtZeroAndAtFullWidth", PunctuationGeometryBranchArmsCoverageTest.haltAdvanceIsRejectedAtZeroAndAtFullWidth);
        run("inlineBoxSpanWithZeroNetStructuralEdgeStillAppliesLeading",
            PunctuationGeometryBranchArmsCoverageTest.inlineBoxSpanWithZeroNetStructuralEdgeStillAppliesLeading);
        run("nonFiniteHaltPlacementIsIgnored", PunctuationGeometryBranchArmsCoverageTest.nonFiniteHaltPlacementIsIgnored);
        run("resolveClustersAppliesGlyphShiftWithUnchangedAdvance",
            PunctuationGeometryBranchArmsCoverageTest.resolveClustersAppliesGlyphShiftWithUnchangedAdvance);
        run("spaceRunRequiresNonEmptyAllSpaceText", PunctuationGeometryBranchArmsCoverageTest.spaceRunRequiresNonEmptyAllSpaceText);
        run("spacingBoundariesAtListEdgesAreFalse", PunctuationGeometryBranchArmsCoverageTest.spacingBoundariesAtListEdgesAreFalse);
        run("spacingPlanIgnoresTargetsOutsideTheBudgets", PunctuationGeometryBranchArmsCoverageTest.spacingPlanIgnoresTargetsOutsideTheBudgets);
        run("typedSpaceWithEmptyTextNeighboursKeepsItsWidth", PunctuationGeometryBranchArmsCoverageTest.typedSpaceWithEmptyTextNeighboursKeepsItsWidth);
        run("unionIgnoresGlyphsWithoutBounds", PunctuationGeometryBranchArmsCoverageTest.unionIgnoresGlyphsWithoutBounds);
        run("virtualGapWithEmptyPreviousTextHasNoNarrowCharacter",
            PunctuationGeometryBranchArmsCoverageTest.virtualGapWithEmptyPreviousTextHasNoNarrowCharacter);
        TestTraceRecorder.flushClass("PunctuationGeometryBranchArmsCoverageTest");
        run("fullyQualifiedEmojiSequencesResolveToOneEmojiRange", UnicodeEmoji17RgiRoleAuditTest.fullyQualifiedEmojiSequencesResolveToOneEmojiRange);
        TestTraceRecorder.flushClass("UnicodeEmoji17RgiRoleAuditTest");
        run("testOpeningBracketAtLineStartCompression", OpeningBracketLineStartTest.testOpeningBracketAtLineStartCompression);
        TestTraceRecorder.flushClass("OpeningBracketLineStartTest");
        run("internalBoundariesAreSuppressedAndOuterEdgesKeepTheGap", VerbatimRangeAutoSpaceTest.internalBoundariesAreSuppressedAndOuterEdgesKeepTheGap);
        run("typedSpaceInsideAVerbatimRangeIsNotNormalised", VerbatimRangeAutoSpaceTest.typedSpaceInsideAVerbatimRangeIsNotNormalised);
        TestTraceRecorder.flushClass("VerbatimRangeAutoSpaceTest");
        run("leadingZeroWidthSpaceCannotCreateAnEmptyAutoWrappedLine", ZeroWidthBreakControlLayoutTest.leadingZeroWidthSpaceCannotCreateAnEmptyAutoWrappedLine);
        run("zeroWidthSpaceIsUnshapedAndProvidesASoftBreakAfterIt", ZeroWidthBreakControlLayoutTest.zeroWidthSpaceIsUnshapedAndProvidesASoftBreakAfterIt);
        TestTraceRecorder.flushClass("ZeroWidthBreakControlLayoutTest");
        run("punctuationNeverResolvesBelowItsBodyWidth", PunctuationBodyFloorInvariantTest.punctuationNeverResolvesBelowItsBodyWidth);
        TestTraceRecorder.flushClass("PunctuationBodyFloorInvariantTest");
        run("cjkMixedSizesAlignByIdeographicBoxBottom", BaselineAlignmentTest.cjkMixedSizesAlignByIdeographicBoxBottom);
        run("cjkPunctuationProvidesIdeographicReferenceWithoutHanBody", BaselineAlignmentTest.cjkPunctuationProvidesIdeographicReferenceWithoutHanBody);
        run("explicitBaselineShiftAppliesToRomanClusters", BaselineAlignmentTest.explicitBaselineShiftAppliesToRomanClusters);
        run("latinInsideCjkUsesSharedRomanBaseline", BaselineAlignmentTest.latinInsideCjkUsesSharedRomanBaseline);
        TestTraceRecorder.flushClass("BaselineAlignmentTest");
        run("interpunctInkEvidenceFreesPairedGlueForTierThreeShrink", InterpunctShrinkOpportunityTest.interpunctInkEvidenceFreesPairedGlueForTierThreeShrink);
        run("preservedInterpunctCodepointKeepsInterpunctClassForTierThreeShrink",
            InterpunctShrinkOpportunityTest.preservedInterpunctCodepointKeepsInterpunctClassForTierThreeShrink);
        TestTraceRecorder.flushClass("InterpunctShrinkOpportunityTest");
        run("LatinTokensAndAmbiguousAsciiCharactersKeepExistingSegmentation",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.LatinTokensAndAmbiguousAsciiCharactersKeepExistingSegmentation);
        run("adjacentImpossibleGroupsDoNotShareHangProvenance", org.tiqian.layout.AsciiPointMarkKinsokuTest.adjacentImpossibleGroupsDoNotShareHangProvenance);
        run("authoredWhitespaceAndMandatoryBreakDoNotCreateContextualKinsoku",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.authoredWhitespaceAndMandatoryBreakDoNotCreateContextualKinsoku);
        run("cjkAttachedAsciiPointMarksCannotStartWrappedLinesAndStayLatin",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.cjkAttachedAsciiPointMarksCannotStartWrappedLinesAndStayLatin);
        run("compressedClosingAndPointMarkPairDoesNotReportAnUnusedHangFallback",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.compressedClosingAndPointMarkPairDoesNotReportAnUnusedHangFallback);
        run("contextualRunCanExtendAProfileHangOnlyWithinTheSameProtectedGroup",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.contextualRunCanExtendAProfileHangOnlyWithinTheSameProtectedGroup);
        run("firstLineIndentUsesTheSameImpossibleMeasureFallback",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.firstLineIndentUsesTheSameImpossibleMeasureFallback);
        run("impossibleMeasureHangsThePointMarkInsteadOfLeavingItAtLineStart",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.impossibleMeasureHangsThePointMarkInsteadOfLeavingItAtLineStart);
        run("kinsokuNoneDisablesClreqButKeepsTheUax14AsciiPointMarkBoundary",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.kinsokuNoneDisablesClreqButKeepsTheUax14AsciiPointMarkBoundary);
        run("leadingPointMarkRunIsSplitFromFollowingLatinText", org.tiqian.layout.AsciiPointMarkKinsokuTest.leadingPointMarkRunIsSplitFromFollowingLatinText);
        run("lineBreakGeometryIncludesBopomofoSpreadWhenChoosingTheFallback",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.lineBreakGeometryIncludesBopomofoSpreadWhenChoosingTheFallback);
        run("mandatoryBreakControlAfterAHungPointMarkStaysInTheTrailingSuffix",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.mandatoryBreakControlAfterAHungPointMarkStaysInTheTrailingSuffix);
        run("pointMarkExposedByASecondStageLatinCutIsSplitFromItsSuffix",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.pointMarkExposedByASecondStageLatinCutIsSplitFromItsSuffix);
        run("pointMarkSplitFromAnOverlongLatinTokenStillCannotStartALine",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.pointMarkSplitFromAnOverlongLatinTokenStillCannotStartALine);
        run("reportedRealWorldParagraphNeverWrapsDirectlyBeforeAnAsciiComma",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.reportedRealWorldParagraphNeverWrapsDirectlyBeforeAnAsciiComma);
        run("styledPointMarkRunCanExtendOneImpossibleMeasureHang",
            org.tiqian.layout.AsciiPointMarkKinsokuTest.styledPointMarkRunCanExtendOneImpossibleMeasureHang);
        TestTraceRecorder.flushClass("AsciiPointMarkKinsokuTest");
        run("attachedReferenceAtParagraphEndHasNoAutospaceGap", org.tiqian.layout.AutoSpaceSingleGapTest.attachedReferenceAtParagraphEndHasNoAutospaceGap);
        run("attachedReferenceBeforeLatinTextGetsTheVirtualCjkLatinGap",
            org.tiqian.layout.AutoSpaceSingleGapTest.attachedReferenceBeforeLatinTextGetsTheVirtualCjkLatinGap);
        run("attachedReferenceBetweenCjkTextDoesNotInventAnAutospaceGap",
            org.tiqian.layout.AutoSpaceSingleGapTest.attachedReferenceBetweenCjkTextDoesNotInventAnAutospaceGap);
        run("autospaceDistinguishesLetterFromDigitAtBoundary", org.tiqian.layout.AutoSpaceSingleGapTest.autospaceDistinguishesLetterFromDigitAtBoundary);
        run("autospaceDoesNotFireBeforeSlashLedLatinTechnicalRun",
            org.tiqian.layout.AutoSpaceSingleGapTest.autospaceDoesNotFireBeforeSlashLedLatinTechnicalRun);
        run("autospaceDoesNotFireBetweenLatinAndCjkPunctuation", org.tiqian.layout.AutoSpaceSingleGapTest.autospaceDoesNotFireBetweenLatinAndCjkPunctuation);
        run("autospaceStillFiresBetweenLatinAndCjkTextEvenWithPunctuationNearby",
            org.tiqian.layout.AutoSpaceSingleGapTest.autospaceStillFiresBetweenLatinAndCjkTextEvenWithPunctuationNearby);
        run("conditionalPunctuationFollowsChineseLanguageResolution",
            org.tiqian.layout.AutoSpaceSingleGapTest.conditionalPunctuationFollowsChineseLanguageResolution);
        run("oneTypedSpaceBecomesOneAutospaceGap", org.tiqian.layout.AutoSpaceSingleGapTest.oneTypedSpaceBecomesOneAutospaceGap);
        run("threeTypedSpacesStillOneGap", org.tiqian.layout.AutoSpaceSingleGapTest.threeTypedSpacesStillOneGap);
        run("twoTypedSpacesAtBoundaryStillCollapseToOneGap", org.tiqian.layout.AutoSpaceSingleGapTest.twoTypedSpacesAtBoundaryStillCollapseToOneGap);
        run("unicodeEastAsianSpacingCoversNarrowScriptsWithoutScriptWhitelists",
            org.tiqian.layout.AutoSpaceSingleGapTest.unicodeEastAsianSpacingCoversNarrowScriptsWithoutScriptWhitelists);
        run("zeroSpacesGetInsertedGaps", org.tiqian.layout.AutoSpaceSingleGapTest.zeroSpacesGetInsertedGaps);
        TestTraceRecorder.flushClass("AutoSpaceSingleGapTest");
        run("attachedReferenceAtSourceEndLaysOutWithoutVirtualBoundary",
            org.tiqian.layout.R3GeometryTailCoverageTest.attachedReferenceAtSourceEndLaysOutWithoutVirtualBoundary);
        run("centeredInkPunctuationKeepsPairedGlue", org.tiqian.layout.R3GeometryTailCoverageTest.centeredInkPunctuationKeepsPairedGlue);
        run("emptyTextProducesNoVisibleLines", org.tiqian.layout.R3GeometryTailCoverageTest.emptyTextProducesNoVisibleLines);
        run("maxLinesCapsVisibleLinesToOne", org.tiqian.layout.R3GeometryTailCoverageTest.maxLinesCapsVisibleLinesToOne);
        run("pureLatinParagraphStillProducesLines", org.tiqian.layout.R3GeometryTailCoverageTest.pureLatinParagraphStillProducesLines);
        run("rubyBaseRangeCrossingClusterBoundariesIsSkipped", org.tiqian.layout.R3GeometryTailCoverageTest.rubyBaseRangeCrossingClusterBoundariesIsSkipped);
        run("spaceRunsResolveBothWideNarrowOrders", org.tiqian.layout.R3GeometryTailCoverageTest.spaceRunsResolveBothWideNarrowOrders);
        TestTraceRecorder.flushClass("R3GeometryTailCoverageTest");
        run("fittingWordHyphenatesOnlyWhenAHyphenatorIsInjected", org.tiqian.layout.HyphenationLayoutTest.fittingWordHyphenatesOnlyWhenAHyphenatorIsInjected);
        run("hyphenIsReservedWithinTheMeasureNotHungPastIt", org.tiqian.layout.HyphenationLayoutTest.hyphenIsReservedWithinTheMeasureNotHungPastIt);
        run("hyphenationIsOnByDefault", org.tiqian.layout.HyphenationLayoutTest.hyphenationIsOnByDefault);
        run("hyphenationIsSkippedWhenStretchingCjkStaysTight", org.tiqian.layout.HyphenationLayoutTest.hyphenationIsSkippedWhenStretchingCjkStaysTight);
        run("reservedHyphenSqueezesPunctuationGlueToPullItIn", org.tiqian.layout.HyphenationLayoutTest.reservedHyphenSqueezesPunctuationGlueToPullItIn);
        run("syllableSplitMatchesTheHyphenatorExactly", org.tiqian.layout.HyphenationLayoutTest.syllableSplitMatchesTheHyphenatorExactly);
        TestTraceRecorder.flushClass("HyphenationLayoutTest");
        run("emphasisDotsHanButNotWestern", org.tiqian.layout.BilingualEmphasisTest.emphasisDotsHanButNotWestern);
        TestTraceRecorder.flushClass("BilingualEmphasisTest");
        run("annotatedBaseReservesHalfEmOnly", org.tiqian.layout.BopomofoLayoutTest.annotatedBaseReservesHalfEmOnly);
        run("annotationLocaleDoesNotReplaceSimplifiedBaseLocale", org.tiqian.layout.BopomofoLayoutTest.annotationLocaleDoesNotReplaceSimplifiedBaseLocale);
        run("decisionKeepsSourceReadingForCopy", org.tiqian.layout.BopomofoLayoutTest.decisionKeepsSourceReadingForCopy);
        run("fontWeightFollowsAnnotatedBasePlusThreeSteps", org.tiqian.layout.BopomofoLayoutTest.fontWeightFollowsAnnotatedBasePlusThreeSteps);
        run("symbolsAndToneRightOfBase", org.tiqian.layout.BopomofoLayoutTest.symbolsAndToneRightOfBase);
        TestTraceRecorder.flushClass("BopomofoLayoutTest");
        run("everyNarrowInlineBoxGetsOuterAutospaceWithoutRoleSpecificCode",
            org.tiqian.layout.InlineBoxLayoutTest.everyNarrowInlineBoxGetsOuterAutospaceWithoutRoleSpecificCode);
        run("inlineEdgesReserveAdvanceAndMoveTheGlyphOrigin", org.tiqian.layout.InlineBoxLayoutTest.inlineEdgesReserveAdvanceAndMoveTheGlyphOrigin);
        TestTraceRecorder.flushClass("InlineBoxLayoutTest");
        run("bracketBoundariesRemainProtectedAcrossWesternSpaces",
            org.tiqian.layout.UnicodePunctuationBoundaryTest.bracketBoundariesRemainProtectedAcrossWesternSpaces);
        run("pairedLatinCurlyQuotesKeepTheirContentAcrossBothLineEdges",
            org.tiqian.layout.UnicodePunctuationBoundaryTest.pairedLatinCurlyQuotesKeepTheirContentAcrossBothLineEdges);
        run("unmatchedElisionApostropheBindsForwardInsteadOfBeingGuessedAsACloser",
            org.tiqian.layout.UnicodePunctuationBoundaryTest.unmatchedElisionApostropheBindsForwardInsteadOfBeingGuessedAsACloser);
        run("unmatchedWesternCurlyDoubleQuotesRetainTheirDirection",
            org.tiqian.layout.UnicodePunctuationBoundaryTest.unmatchedWesternCurlyDoubleQuotesRetainTheirDirection);
        run("westernBaselineSurvivesClreqKinsokuNone", org.tiqian.layout.UnicodePunctuationBoundaryTest.westernBaselineSurvivesClreqKinsokuNone);
        run("westernBracketsTouchingCjkExposeAllFourStretchBoundaries",
            org.tiqian.layout.UnicodePunctuationBoundaryTest.westernBracketsTouchingCjkExposeAllFourStretchBoundaries);
        run("westernClosingPunctuationCannotBeginAnAutomaticLine",
            org.tiqian.layout.UnicodePunctuationBoundaryTest.westernClosingPunctuationCannotBeginAnAutomaticLine);
        run("westernOpeningBracketsCannotEndAnAutomaticLine", org.tiqian.layout.UnicodePunctuationBoundaryTest.westernOpeningBracketsCannotEndAnAutomaticLine);
        TestTraceRecorder.flushClass("UnicodePunctuationBoundaryTest");
        run("faceSelectionUsesTheDisplayTextThatWasActuallyShaped",
            org.tiqian.layout.FontInstanceMetricsRequestTest.faceSelectionUsesTheDisplayTextThatWasActuallyShaped);
        run("perSpanWeightAndItalicReachTheMetricsResolver", org.tiqian.layout.FontInstanceMetricsRequestTest.perSpanWeightAndItalicReachTheMetricsResolver);
        run("rubyMetricsUseTheSameItalicInstanceAsRubyShaping",
            org.tiqian.layout.FontInstanceMetricsRequestTest.rubyMetricsUseTheSameItalicInstanceAsRubyShaping);
        TestTraceRecorder.flushClass("FontInstanceMetricsRequestTest");
        Console.log("all CoreUnitsGeometryTest checks passed");
        run("fillPushInCompressesSourceSpaceToPromoteEmergencyBreakToSyllable",
            org.tiqian.layout.LineAdjustmentPushInTest.fillPushInCompressesSourceSpaceToPromoteEmergencyBreakToSyllable);
        run("fillPushInCrossesIntermediateCleanerBoundaryToRefillAtSelectedTier",
            org.tiqian.layout.LineAdjustmentPushInTest.fillPushInCrossesIntermediateCleanerBoundaryToRefillAtSelectedTier);
        run("fillPushInDoesNotPromoteEmergencyBreakWhenCleanerBoundaryStillLeavesDeficit",
            org.tiqian.layout.LineAdjustmentPushInTest.fillPushInDoesNotPromoteEmergencyBreakWhenCleanerBoundaryStillLeavesDeficit);
        run("fillPushInExtendsPastForbiddenLineEndHead", org.tiqian.layout.LineAdjustmentPushInTest.fillPushInExtendsPastForbiddenLineEndHead);
        run("fillPushInPullsMinimalGroupToAvoidForbiddenNextHead",
            org.tiqian.layout.LineAdjustmentPushInTest.fillPushInPullsMinimalGroupToAvoidForbiddenNextHead);
        run("noShrinkFillPushInCanContinueUntilTheLineIsNoLongerLoose",
            org.tiqian.layout.LineAdjustmentPushInTest.noShrinkFillPushInCanContinueUntilTheLineIsNoLongerLoose);
        run("pushInFirstCompressesSomeBoundariesPushOutOnlyNone",
            org.tiqian.layout.LineAdjustmentPushInTest.pushInFirstCompressesSomeBoundariesPushOutOnlyNone);
        run("pushInFirstDoesNotCompressEveryLine", org.tiqian.layout.LineAdjustmentPushInTest.pushInFirstDoesNotCompressEveryLine);
        TestTraceRecorder.flushClass("LineAdjustmentPushInTest");
        run("dashInkCenteringWithShapedBounds", org.tiqian.layout.LineAdjustmentStageJfTest.dashInkCenteringWithShapedBounds);
        run("dashInkCenteringWithWideBoundsReturnsSameGlyph", org.tiqian.layout.LineAdjustmentStageJfTest.dashInkCenteringWithWideBoundsReturnsSameGlyph);
        run("hyphenSqueezeConsumesPairedLeadingAndTrailingGlueUnderTaiwanProfile",
            org.tiqian.layout.LineAdjustmentStageJfTest.hyphenSqueezeConsumesPairedLeadingAndTrailingGlueUnderTaiwanProfile);
        run("inlineObjectSeparatorSpaceTrimEdge", org.tiqian.layout.LineAdjustmentStageJfTest.inlineObjectSeparatorSpaceTrimEdge);
        run("inlineObjectWithZeroDiscardableAdvance", org.tiqian.layout.LineAdjustmentStageJfTest.inlineObjectWithZeroDiscardableAdvance);
        TestTraceRecorder.flushClass("LineAdjustmentStageJfTest");
        run("ambiguousGlyphClusterMappingFallsBackToPolicyWithRecordedReason",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.ambiguousGlyphClusterMappingFallsBackToPolicyWithRecordedReason);
        run("coalesceSetIsDrivenByProfile", org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.coalesceSetIsDrivenByProfile);
        run("dashCoverageTargetUsesTheDashSpanFontSize", org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.dashCoverageTargetUsesTheDashSpanFontSize);
        run("dashInkCentersWithinTheTwoEmBodyWhenTheFontRuleUnderfills",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.dashInkCentersWithinTheTwoEmBodyWhenTheFontRuleUnderfills);
        run("dashSubstitutionIsKeptWhenInkFillsTheTwoEmAdvance",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.dashSubstitutionIsKeptWhenInkFillsTheTwoEmAdvance);
        run("dashSubstitutionRollsBackWhenFallbackReportsAFullOneEmGlyph",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.dashSubstitutionRollsBackWhenFallbackReportsAFullOneEmGlyph);
        run("dashSubstitutionRollsBackWhenInkDoesNotFillTheTwoEmAdvance",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.dashSubstitutionRollsBackWhenInkDoesNotFillTheTwoEmAdvance);
        run("ellipsisSubstitutionRollsBackWhenCoverageCannotBeVerified",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.ellipsisSubstitutionRollsBackWhenCoverageCannotBeVerified);
        run("honorsProfilePunctuationGlyphPolicy", org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.honorsProfilePunctuationGlyphPolicy);
        run("multiCharacterPunctuationUsesCharacterLocalInkBounds",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.multiCharacterPunctuationUsesCharacterLocalInkBounds);
        run("preservesOpenTypeFeaturesAsFinalGlyphRunBoundaries",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.preservesOpenTypeFeaturesAsFinalGlyphRunBoundaries);
        run("preservesSourceTextWhenUsingClreqRecommendedDisplayGlyphs",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.preservesSourceTextWhenUsingClreqRecommendedDisplayGlyphs);
        run("rolledBackDashStillKeepsItsBoundariesClosedUnderJustification",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.rolledBackDashStillKeepsItsBoundariesClosedUnderJustification);
        run("shapingWithoutBoundsProducesNamedProfileFallback",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.shapingWithoutBoundsProducesNamedProfileFallback);
        run("stubShaperReportsProfileFallbackWhenInkBoundsAreUnavailable",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.stubShaperReportsProfileFallbackWhenInkBoundsAreUnavailable);
        run("substitutionIsKeptWhenFontCoversTheGlyph", org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.substitutionIsKeptWhenFontCoversTheGlyph);
        run("substitutionRollsBackToSourceTextWhenFontLacksTheGlyph",
            org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.substitutionRollsBackToSourceTextWhenFontLacksTheGlyph);
        run("usesTwoEmAdvanceForRecommendedDashCodepoint", org.tiqian.layout.DisplayGlyphSubstitutionEngineTest.usesTwoEmAdvanceForRecommendedDashCodepoint);
        TestTraceRecorder.flushClass("DisplayGlyphSubstitutionEngineTest");
        run("attachedFootnoteTrailingGlueTrimsWhenTheLineEndsAtTheRun",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.attachedFootnoteTrailingGlueTrimsWhenTheLineEndsAtTheRun);
        run("attachedObjectMarkHangsInsteadOfLeavingTheSeparatorAtAnEdge",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.attachedObjectMarkHangsInsteadOfLeavingTheSeparatorAtAnEdge);
        run("baselineShiftSpanRaisesTheFinalClusterShift", org.tiqian.layout.LineAdjustmentStageCoverageTest.baselineShiftSpanRaisesTheFinalClusterShift);
        run("blankMiddleLineSkipsEveryEdgePass", org.tiqian.layout.LineAdjustmentStageCoverageTest.blankMiddleLineSkipsEveryEdgePass);
        run("dashRunWithoutInkBoundsKeepsSyntheticGlyphs", org.tiqian.layout.LineAdjustmentStageCoverageTest.dashRunWithoutInkBoundsKeepsSyntheticGlyphs);
        run("emergencySelectedBreakOpensThePreferredTrackingSpan",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.emergencySelectedBreakOpensThePreferredTrackingSpan);
        run("emptyTextYieldsZeroHeightWithoutLines", org.tiqian.layout.LineAdjustmentStageCoverageTest.emptyTextYieldsZeroHeightWithoutLines);
        run("formulaLineEndDiscardsTheTrailingBoundaryAdvance",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.formulaLineEndDiscardsTheTrailingBoundaryAdvance);
        run("formulaObjectWithoutBoundaryDiscardsNothingAtLineEnd",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.formulaObjectWithoutBoundaryDiscardsNothingAtLineEnd);
        run("hyphenSqueezeConsumesOpeningAndClosingBracketGlueChannels",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.hyphenSqueezeConsumesOpeningAndClosingBracketGlueChannels);
        run("hyphenSqueezeConsumesTheInterpunctPairedChannel",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.hyphenSqueezeConsumesTheInterpunctPairedChannel);
        run("hyphenSqueezeConsumesTheWordSpaceRawAdvanceChannel",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.hyphenSqueezeConsumesTheWordSpaceRawAdvanceChannel);
        run("hyphenSqueezeFallsBackToZeroUsedGlueWhenTheLineAlreadyFits",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.hyphenSqueezeFallsBackToZeroUsedGlueWhenTheLineAlreadyFits);
        run("loneLatinClusterMergesBothAutoSpaceEdgeTrimsIntoOneKey",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.loneLatinClusterMergesBothAutoSpaceEdgeTrimsIntoOneKey);
        run("loneMandatoryBreakEmitsTwoZeroWidthLines", org.tiqian.layout.LineAdjustmentStageCoverageTest.loneMandatoryBreakEmitsTwoZeroWidthLines);
        run("mandatoryBreakMiddleLineSkipsItsJustificationPlan",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.mandatoryBreakMiddleLineSkipsItsJustificationPlan);
        run("technicalLineBodyStretchRejectsTheCleanTierAndReplays",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.technicalLineBodyStretchRejectsTheCleanTierAndReplays);
        run("tinyTechnicalTrackingStaysBelowTheRejectionThreshold",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.tinyTechnicalTrackingStaysBelowTheRejectionThreshold);
        run("trailingMandatoryBreakEmitsTerminalEmptyLineWithoutHyphen",
            org.tiqian.layout.LineAdjustmentStageCoverageTest.trailingMandatoryBreakEmitsTerminalEmptyLineWithoutHyphen);
        run("zeroAdvanceEdgeSpaceIsNeverCollapsed", org.tiqian.layout.LineAdjustmentStageCoverageTest.zeroAdvanceEdgeSpaceIsNeverCollapsed);
        TestTraceRecorder.flushClass("LineAdjustmentStageCoverageTest");
        if (failures > 0) {
            Process.exit(1);
        }
        run("allCapsAbbreviationIsNeverBroken", org.tiqian.layout.LineBreakRepairEngineTest.allCapsAbbreviationIsNeverBroken);
        run("camelCaseTokenBreaksAtTheHumpWithoutAHyphen", org.tiqian.layout.LineBreakRepairEngineTest.camelCaseTokenBreaksAtTheHumpWithoutAHyphen);
        run("greedyBreakerProducesMultipleLinesWhenWidthOverflows",
            org.tiqian.layout.LineBreakRepairEngineTest.greedyBreakerProducesMultipleLinesWhenWidthOverflows);
        run("hyphenatedCompoundBreaksAtExistingHyphenWithoutAddingOne",
            org.tiqian.layout.LineBreakRepairEngineTest.hyphenatedCompoundBreaksAtExistingHyphenWithoutAddingOne);
        run("latinSolidusBreaksAfterSlashWithoutAddingHyphen", org.tiqian.layout.LineBreakRepairEngineTest.latinSolidusBreaksAfterSlashWithoutAddingHyphen);
        run("longAllCapsOpaqueTokenHardBreaksWithoutSyntheticHyphen",
            org.tiqian.layout.LineBreakRepairEngineTest.longAllCapsOpaqueTokenHardBreaksWithoutSyntheticHyphen);
        run("longLetterBlobStaysOpaqueEvenWhenTailLooksHyphenatable",
            org.tiqian.layout.LineBreakRepairEngineTest.longLetterBlobStaysOpaqueEvenWhenTailLooksHyphenatable);
        run("longOpaqueTokenCanBreakEvenWhenItFitsAloneButNotAfterCjkPrefix",
            org.tiqian.layout.LineBreakRepairEngineTest.longOpaqueTokenCanBreakEvenWhenItFitsAloneButNotAfterCjkPrefix);
        run("nonLexicalLetterRunAfterCjkPullsPrefixOntoLooseLineWithoutSyntheticHyphen",
            org.tiqian.layout.LineBreakRepairEngineTest.nonLexicalLetterRunAfterCjkPullsPrefixOntoLooseLineWithoutSyntheticHyphen);
        run("opaqueLatinTokenAfterCjkPullsPrefixOntoLooseLine", org.tiqian.layout.LineBreakRepairEngineTest.opaqueLatinTokenAfterCjkPullsPrefixOntoLooseLine);
        run("overlongLatinWordHardBreaksWithAHangingHyphen", org.tiqian.layout.LineBreakRepairEngineTest.overlongLatinWordHardBreaksWithAHangingHyphen);
        run("overlongOpaqueLatinTokenHardBreaksWithoutSyntheticHyphen",
            org.tiqian.layout.LineBreakRepairEngineTest.overlongOpaqueLatinTokenHardBreaksWithoutSyntheticHyphen);
        run("progressiveTechnicalBreakFallsThroughStructuralTierBeforeOverstretchingOutsideText",
            org.tiqian.layout.LineBreakRepairEngineTest.progressiveTechnicalBreakFallsThroughStructuralTierBeforeOverstretchingOutsideText);
        run("progressiveTechnicalBreakKeepsCjkBodyUnstretchedInEveryStrategy",
            org.tiqian.layout.LineBreakRepairEngineTest.progressiveTechnicalBreakKeepsCjkBodyUnstretchedInEveryStrategy);
        run("progressiveTechnicalCleanBreakMayNotStretchEarlierOpaqueToken",
            org.tiqian.layout.LineBreakRepairEngineTest.progressiveTechnicalCleanBreakMayNotStretchEarlierOpaqueToken);
        run("progressiveTechnicalEmergencyIsExposedByCurrentLineStretchNotFullMeasure",
            org.tiqian.layout.LineBreakRepairEngineTest.progressiveTechnicalEmergencyIsExposedByCurrentLineStretchNotFullMeasure);
        run("progressiveTechnicalHardBreakOverridesNumberRunCohesion",
            org.tiqian.layout.LineBreakRepairEngineTest.progressiveTechnicalHardBreakOverridesNumberRunCohesion);
        run("progressiveTechnicalStructuralBreakFallsThroughToEmergencyBeforeTracking",
            org.tiqian.layout.LineBreakRepairEngineTest.progressiveTechnicalStructuralBreakFallsThroughToEmergencyBeforeTracking);
        run("unbrokenProgressiveSpanUsesSourceSpaceThenKeepsBodyOpportunitiesAvailable",
            org.tiqian.layout.LineBreakRepairEngineTest.unbrokenProgressiveSpanUsesSourceSpaceThenKeepsBodyOpportunitiesAvailable);
        run("urlLikeLatinTokenBreaksAtSeparatorsWithoutSyntheticHyphen",
            org.tiqian.layout.LineBreakRepairEngineTest.urlLikeLatinTokenBreaksAtSeparatorsWithoutSyntheticHyphen);
        TestTraceRecorder.flushClass("LineBreakRepairEngineTest");
        run("bibliographicNumericLocatorExposesStructuralBreaks",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.bibliographicNumericLocatorExposesStructuralBreaks);
        run("hangingPunctuationFillsLineToMeasureAndOverflowsVisual",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.hangingPunctuationFillsLineToMeasureAndOverflowsVisual);
        run("kinsokuCarriesPreviousClusterWhenLineWouldStartWithForbiddenPunctuation",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.kinsokuCarriesPreviousClusterWhenLineWouldStartWithForbiddenPunctuation);
        run("kinsokuFallsBackToLeaveRaggedWhenPreviousLineCannotSpareACluster",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.kinsokuFallsBackToLeaveRaggedWhenPreviousLineCannotSpareACluster);
        run("kinsokuLeavesGreedyBreakAloneWhenNoForbiddenPunctAtLineStart",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.kinsokuLeavesGreedyBreakAloneWhenNoForbiddenPunctAtLineStart);
        run("kinsokuLevelNoneLeavesForbiddenMarksAtLineStart",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.kinsokuLevelNoneLeavesForbiddenMarksAtLineStart);
        run("kinsokuLevelStrictForbidsDashAtLineStart", org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.kinsokuLevelStrictForbidsDashAtLineStart);
        run("kinsokuPushesLineStartPunctuationIntoPreviousLineWhenTrailingGlueCanShrink",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.kinsokuPushesLineStartPunctuationIntoPreviousLineWhenTrailingGlueCanShrink);
        run("lineEndKinsokuMovesDanglingOpenerToNextLine", org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.lineEndKinsokuMovesDanglingOpenerToNextLine);
        run("longLatinSentenceWrapsAtWordBoundaries", org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.longLatinSentenceWrapsAtWordBoundaries);
        run("numberWithSuffixSymbolNeverSplitsAcrossLines", org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.numberWithSuffixSymbolNeverSplitsAcrossLines);
        run("ordinaryNumericFormsDoNotBecomeBibliographicLocators",
            org.tiqian.layout.KinsokuAndCohesionRepairEngineTest.ordinaryNumericFormsDoNotBecomeBibliographicLocators);
        TestTraceRecorder.flushClass("KinsokuAndCohesionRepairEngineTest");
        run("hashPieceInsideTechnicalUrlSkipsSyllableClassification",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.hashPieceInsideTechnicalUrlSkipsSyllableClassification);
        run("longAllCapsWesternWordDoesNotBecomeTrackingEligible",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.longAllCapsWesternWordDoesNotBecomeTrackingEligible);
        run("ordinaryWesternProseIsNeverInferredAsTrackingEligible",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.ordinaryWesternProseIsNeverInferredAsTrackingEligible);
        run("plainOpaqueHardBreakKeepsCombiningGraphemeIntact",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.plainOpaqueHardBreakKeepsCombiningGraphemeIntact);
        run("rejectedLetterDigitStructuralOffsetsRemainAvailableAsEmergencyCuts",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.rejectedLetterDigitStructuralOffsetsRemainAvailableAsEmergencyCuts);
        run("repeatedPlainTokenGetsNarrowNonLexicalAuthorization",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.repeatedPlainTokenGetsNarrowNonLexicalAuthorization);
        run("standaloneTechnicalHashUsesTrackingToFillEveryAutoWrappedLine",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.standaloneTechnicalHashUsesTrackingToFillEveryAutoWrappedLine);
        run("technicalIdentifierRelabelsLooseLetterDigitBoundaryAsEmergency",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.technicalIdentifierRelabelsLooseLetterDigitBoundaryAsEmergency);
        run("technicalTrackingDoesNotOpenEdgesTouchingInlineObjectsOrZeroWidthControls",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.technicalTrackingDoesNotOpenEdgesTouchingInlineObjectsOrZeroWidthControls);
        run("unannotatedUrlDoesNotAuthorizeTrackingAcrossOrdinaryPathComponents",
            org.tiqian.layout.EmergencyGraphemeTrackingTest.unannotatedUrlDoesNotAuthorizeTrackingAcrossOrdinaryPathComponents);
        TestTraceRecorder.flushClass("EmergencyGraphemeTrackingTest");
        run("cacheKeyDistinguishesTypographyDecorationsAndSpans",
            org.tiqian.layout.WidthIndependentAnnotationCacheTest.cacheKeyDistinguishesTypographyDecorationsAndSpans);
        run("cachedAndUncachedEnginesProduceIdenticalLayoutResultsAcrossWidths",
            org.tiqian.layout.WidthIndependentAnnotationCacheTest.cachedAndUncachedEnginesProduceIdenticalLayoutResultsAcrossWidths);
        run("lruCacheEvictsOldestEntriesWhenCapacityExceeded",
            org.tiqian.layout.WidthIndependentAnnotationCacheTest.lruCacheEvictsOldestEntriesWhenCapacityExceeded);
        run("reflowFuzzingRandomSequenceProducesExactOutput",
            org.tiqian.layout.WidthIndependentAnnotationCacheTest.reflowFuzzingRandomSequenceProducesExactOutput);
        run("relayoutWithDifferentWidthHitsCacheAndSkipsShaper",
            org.tiqian.layout.WidthIndependentAnnotationCacheTest.relayoutWithDifferentWidthHitsCacheAndSkipsShaper);
        TestTraceRecorder.flushClass("WidthIndependentAnnotationCacheTest");
        run("layoutDecisionDumpsMatchEmbeddedGolden", org.tiqian.layout.LayoutDumpGoldenParityTest.layoutDecisionDumpsMatchEmbeddedGolden);
        TestTraceRecorder.flushClass("LayoutDumpGoldenParityTest");
        run("attachedRunExposesTheProseClustersOnItsTwoSides",
            org.tiqian.layout.AttachedInlineBoundaryRelocationTest.attachedRunExposesTheProseClustersOnItsTwoSides);
        run("attachedRunAtParagraphEndHasNoVirtualRightNeighbor",
            org.tiqian.layout.AttachedInlineBoundaryRelocationTest.attachedRunAtParagraphEndHasNoVirtualRightNeighbor);
        run("punctuationAfterFootnoteIsJudgedAgainstThePrecedingPunctuation",
            org.tiqian.layout.AttachedInlineBoundaryRelocationTest.punctuationAfterFootnoteIsJudgedAgainstThePrecedingPunctuation);
        run("closingQuoteBeforeFootnoteAndBodyKeepsItsNaturalTrailingGlue",
            org.tiqian.layout.AttachedInlineBoundaryRelocationTest.closingQuoteBeforeFootnoteAndBodyKeepsItsNaturalTrailingGlue);
        run("closingQuoteBeforeParagraphEndFootnoteHasNoTrailingGlue",
            org.tiqian.layout.AttachedInlineBoundaryRelocationTest.closingQuoteBeforeParagraphEndFootnoteHasNoTrailingGlue);
        run("attachedReferenceNeverStartsAWrappedLine", org.tiqian.layout.AttachedInlineBoundaryRelocationTest.attachedReferenceNeverStartsAWrappedLine);
        TestTraceRecorder.flushClass("AttachedInlineVirtualAdjacencyTest");
        run("clusterPredicatesAndCurlyQuoteFeatures", org.tiqian.layout.ParagraphShapingStageCoverageTest.clusterPredicatesAndCurlyQuoteFeatures);
        run("dashSubstitutionRollbackAndCoverageBranches", org.tiqian.layout.ParagraphShapingStageCoverageTest.dashSubstitutionRollbackAndCoverageBranches);
        run("directShapeParagraphEdgeCases", org.tiqian.layout.ParagraphShapingStageCoverageTest.directShapeParagraphEdgeCases);
        run("hyphenAdvanceFallbackWhenShaperReturnsEmptyClusters",
            org.tiqian.layout.ParagraphShapingStageCoverageTest.hyphenAdvanceFallbackWhenShaperReturnsEmptyClusters);
        run("latinSegmentationAndCutsBranches", org.tiqian.layout.ParagraphShapingStageCoverageTest.latinSegmentationAndCutsBranches);
        run("latinSeparatorCutsAndSolidusBranches", org.tiqian.layout.ParagraphShapingStageCoverageTest.latinSeparatorCutsAndSolidusBranches);
        run("latinSeparatorCutsExhaustiveBranches", org.tiqian.layout.ParagraphShapingStageCoverageTest.latinSeparatorCutsExhaustiveBranches);
        run("latinSeparatorTokensCoverUrlLeadingSlashAndDashLocators",
            org.tiqian.layout.ParagraphShapingStageCoverageTest.latinSeparatorTokensCoverUrlLeadingSlashAndDashLocators);
        run("latinWordCutsLoHiAndEmptyBranches", org.tiqian.layout.ParagraphShapingStageCoverageTest.latinWordCutsLoHiAndEmptyBranches);
        run("mapToClusterRangeWithZeroAndPositiveAdvance", org.tiqian.layout.ParagraphShapingStageCoverageTest.mapToClusterRangeWithZeroAndPositiveAdvance);
        run("multiClusterShaperForWordCutsAndOpaqueHardCuts",
            org.tiqian.layout.ParagraphShapingStageCoverageTest.multiClusterShaperForWordCutsAndOpaqueHardCuts);
        run("progressiveTechnicalSpanBreaksAndTiers", org.tiqian.layout.ParagraphShapingStageCoverageTest.progressiveTechnicalSpanBreaksAndTiers);
        run("progressiveTechnicalTierPriorityAndFalseBranches",
            org.tiqian.layout.ParagraphShapingStageCoverageTest.progressiveTechnicalTierPriorityAndFalseBranches);
        run("progressiveTierLoopRevisitsOffsetsWithLowerPriorityTiers",
            org.tiqian.layout.ParagraphShapingStageCoverageTest.progressiveTierLoopRevisitsOffsetsWithLowerPriorityTiers);
        TestTraceRecorder.flushClass("ParagraphShapingStageCoverageTest");
        run("rubyDoesNotChangeLineBoxAndCentresOverBase", org.tiqian.layout.RubyLayoutTest.rubyDoesNotChangeLineBoxAndCentresOverBase);
        run("rubyOnOneLineKeepsTheWholeBaselineGridStable", org.tiqian.layout.RubyLayoutTest.rubyOnOneLineKeepsTheWholeBaselineGridStable);
        run("tightLineHeightRaisesOnlyTheAnnotatedLineByDefault", org.tiqian.layout.RubyLayoutTest.tightLineHeightRaisesOnlyTheAnnotatedLineByDefault);
        run("uniformModeAddsTheSameDeficitToEveryLine", org.tiqian.layout.RubyLayoutTest.uniformModeAddsTheSameDeficitToEveryLine);
        run("rubyVerticalGeometryUsesLatinMetricsNotReadingInk", org.tiqian.layout.RubyLayoutTest.rubyVerticalGeometryUsesLatinMetricsNotReadingInk);
        run("noRubyIsUnchanged", org.tiqian.layout.RubyLayoutTest.noRubyIsUnchanged);
        run("wideAdjacentReadingsSpreadButNarrowDoNot", org.tiqian.layout.RubyLayoutTest.wideAdjacentReadingsSpreadButNarrowDoNot);
        TestTraceRecorder.flushClass("RubyLayoutTest");
        run("bopomofoAndDecorationLeadingBlankExhaustiveBranches",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.bopomofoAndDecorationLeadingBlankExhaustiveBranches);
        run("bopomofoDecisionsAllTonesAndSymbolCounts", org.tiqian.layout.AnnotationGeometryStageCoverageTest.bopomofoDecisionsAllTonesAndSymbolCounts);
        run("bopomofoDecisionsMultiGlyphMinMaxAndEmptyPlacements",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.bopomofoDecisionsMultiGlyphMinMaxAndEmptyPlacements);
        run("bopomofoOverLatinClustersCoversCrossMetricLookup",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.bopomofoOverLatinClustersCoversCrossMetricLookup);
        run("decorationDecisionsEmphasisOnHanPunctuationAndWestern",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.decorationDecisionsEmphasisOnHanPunctuationAndWestern);
        run("decorationSegmentsLeadingAndTrailingBlanks", org.tiqian.layout.AnnotationGeometryStageCoverageTest.decorationSegmentsLeadingAndTrailingBlanks);
        run("decorationSegmentsMourningProperNounBookTitleAndShortening",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.decorationSegmentsMourningProperNounBookTitleAndShortening);
        run("directResolveAnnotationGeometryEmptyLineRangesAndGapAtLineEdges",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.directResolveAnnotationGeometryEmptyLineRangesAndGapAtLineEdges);
        run("directResolveAnnotationGeometryFallbackBranches",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.directResolveAnnotationGeometryFallbackBranches);
        run("inlineObjectDecisionsWithPreferredStretchAndFixed",
            org.tiqian.layout.AnnotationGeometryStageCoverageTest.inlineObjectDecisionsWithPreferredStretchAndFixed);
        run("rubyDecisionsPinyinSingleAndSplitLines", org.tiqian.layout.AnnotationGeometryStageCoverageTest.rubyDecisionsPinyinSingleAndSplitLines);
        TestTraceRecorder.flushClass("AnnotationGeometryStageCoverageTest");
        run("dashAndSolidusBoundariesInsideTechnicalSpansNeverStretch",
            org.tiqian.layout.LineBreakPlanningStageCoverageTest.dashAndSolidusBoundariesInsideTechnicalSpansNeverStretch);
        run("emergencyBoundaryEligibilitySkipsInlineObjectBoundaries",
            org.tiqian.layout.LineBreakPlanningStageCoverageTest.emergencyBoundaryEligibilitySkipsInlineObjectBoundaries);
        run("emergencyBoundaryEligibilitySkipsZeroWidthAndMandatoryControls",
            org.tiqian.layout.LineBreakPlanningStageCoverageTest.emergencyBoundaryEligibilitySkipsZeroWidthAndMandatoryControls);
        run("explicitZeroLineHeightKeepsTheControlParagraphAtZeroHeight",
            org.tiqian.layout.LineBreakPlanningStageCoverageTest.explicitZeroLineHeightKeepsTheControlParagraphAtZeroHeight);
        run("overlappingTechnicalSpansKeepTheFirstBoundaryReason",
            org.tiqian.layout.LineBreakPlanningStageCoverageTest.overlappingTechnicalSpansKeepTheFirstBoundaryReason);
        run("pushOutFirstTakesFewerFillPushInsThanPushInFirst",
            org.tiqian.layout.LineBreakPlanningStageCoverageTest.pushOutFirstTakesFewerFillPushInsThanPushInFirst);
        TestTraceRecorder.flushClass("LineBreakPlanningStageCoverageTest");
        run("testAdjustableInlineBoundaryRightClustersNoStretchBoundaries",
            org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testAdjustableInlineBoundaryRightClustersNoStretchBoundaries);
        run("testAsciiPointMarkKinsokuLineStart", org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testAsciiPointMarkKinsokuLineStart);
        run("testClusterCrossesFontDecisionThrows", org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testClusterCrossesFontDecisionThrows);
        run("testEmergencyTrackingBoundaryWhitespaceAndEmpty",
            org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testEmergencyTrackingBoundaryWhitespaceAndEmpty);
        run("testEmergencyTrackingEligibilityDecisionsBranches",
            org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testEmergencyTrackingEligibilityDecisionsBranches);
        run("testFontDecisionWithNoMatchingClustersUsesTextSubstring",
            org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testFontDecisionWithNoMatchingClustersUsesTextSubstring);
        run("testInlineObjectKinsokuLineStart", org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testInlineObjectKinsokuLineStart);
        run("testProgressiveBreakOffsetsUnmappedClusterIndex",
            org.tiqian.layout.LineBreakPlanningStageCoverage2Test.testProgressiveBreakOffsetsUnmappedClusterIndex);
        TestTraceRecorder.flushClass("LineBreakPlanningStageCoverage2Test");
        run("keepsLatinTechnicalPunctuationInLatinRun", QuoteClassificationEngineTest.keepsLatinTechnicalPunctuationInLatinRun);
        run("classifiesAsciiBracketsAsLatinRegardlessOfSurroundingContext",
            QuoteClassificationEngineTest.classifiesAsciiBracketsAsLatinRegardlessOfSurroundingContext);
        run("classifiesAsciiBracketsAsLatinInsidePureCjkContent", QuoteClassificationEngineTest.classifiesAsciiBracketsAsLatinInsidePureCjkContent);
        run("asciiClosingBracketWithCjkInteriorIsForbiddenAtLineStart", QuoteClassificationEngineTest.asciiClosingBracketWithCjkInteriorIsForbiddenAtLineStart);
        run("asciiOpeningBracketWithCjkInteriorIsForbiddenAtLineEnd", QuoteClassificationEngineTest.asciiOpeningBracketWithCjkInteriorIsForbiddenAtLineEnd);
        run("keepsTextStartLatinQuotePairInLatinRun", QuoteClassificationEngineTest.keepsTextStartLatinQuotePairInLatinRun);
        run("mixedQuoteContextsReachTheFontAndPunctuationPipeline", QuoteClassificationEngineTest.mixedQuoteContextsReachTheFontAndPunctuationPipeline);
        run("quoteRolesSurviveStyleAndSourceBoundaries", QuoteClassificationEngineTest.quoteRolesSurviveStyleAndSourceBoundaries);
        run("adjacentQuotedListItemsKeepCjkQuoteGeometryAcrossMixedContent",
            QuoteClassificationEngineTest.adjacentQuotedListItemsKeepCjkQuoteGeometryAcrossMixedContent);
        run("mi10sAdjacentLatinTranscriptionsKeepTheFinalQuotePairInCjkContext",
            QuoteClassificationEngineTest.mi10sAdjacentLatinTranscriptionsKeepTheFinalQuotePairInCjkContext);
        run("skipsNeutralDashBeforeLatinQuotePairInLayout", QuoteClassificationEngineTest.skipsNeutralDashBeforeLatinQuotePairInLayout);
        run("keepsSlashLedLatinTechnicalRunOutOfCjkPunctuationGeometry",
            QuoteClassificationEngineTest.keepsSlashLedLatinTechnicalRunOutOfCjkPunctuationGeometry);
        run("recordsRoleOverridesForResolvedQuotePairs", QuoteClassificationEngineTest.recordsRoleOverridesForResolvedQuotePairs);
        run("mixedChineseQuestionAtParagraphStartKeepsCjkQuoteGeometry",
            QuoteClassificationEngineTest.mixedChineseQuestionAtParagraphStartKeepsCjkQuoteGeometry);
        run("keepsNumberedCjkQuotePairOnCjkFace", QuoteClassificationEngineTest.keepsNumberedCjkQuotePairOnCjkFace);
        run("requestsFullWidthCjkQuotesAndSynthesizesTheCellWhenTheFontStaysProportional",
            QuoteClassificationEngineTest.requestsFullWidthCjkQuotesAndSynthesizesTheCellWhenTheFontStaysProportional);
        run("leavesLatinContextCurlyQuotesOutsideCjkPunctuationGeometry",
            QuoteClassificationEngineTest.leavesLatinContextCurlyQuotesOutsideCjkPunctuationGeometry);
        run("keepsContractionApostropheLatinInsideCjkSingleQuotes", QuoteClassificationEngineTest.keepsContractionApostropheLatinInsideCjkSingleQuotes);
        run("keepsLatinWordInternalCurlyQuotesInLatinRunInsideMixedParagraph",
            QuoteClassificationEngineTest.keepsLatinWordInternalCurlyQuotesInLatinRunInsideMixedParagraph);
        run("supportsSupplementaryLettersInsideLatinWordInternalQuotes",
            QuoteClassificationEngineTest.supportsSupplementaryLettersInsideLatinWordInternalQuotes);
        run("keepsLetterBoundedWordInternalQuotesLatin", QuoteClassificationEngineTest.keepsLetterBoundedWordInternalQuotesLatin);
        run("keepsDigitContentInsideLetterBoundedQuotesLatin", QuoteClassificationEngineTest.keepsDigitContentInsideLetterBoundedQuotesLatin);
        run("keepsDigitBoundedWordInternalQuotesCjk", QuoteClassificationEngineTest.keepsDigitBoundedWordInternalQuotesCjk);
        run("keepsFullwidthLetterBoundedWordInternalQuotesCjk", QuoteClassificationEngineTest.keepsFullwidthLetterBoundedWordInternalQuotesCjk);
        run("keepsEmptyWordInternalQuotesLatin", QuoteClassificationEngineTest.keepsEmptyWordInternalQuotesLatin);
        run("keepsAstralLetterBoundedWordInternalQuotesLatin", QuoteClassificationEngineTest.keepsAstralLetterBoundedWordInternalQuotesLatin);
        run("keepsSpaceInsidePairOutOfWordInternalFastPathLatin", QuoteClassificationEngineTest.keepsSpaceInsidePairOutOfWordInternalFastPathLatin);
        run("keepsDigitBoundedSingleQuotePairCjkViaEnclosingQuotation", QuoteClassificationEngineTest.keepsDigitBoundedSingleQuotePairCjkViaEnclosingQuotation);
        run("resolvesDigitBoundUnmatchedQuotesAsPrimes", QuoteClassificationEngineTest.resolvesDigitBoundUnmatchedQuotesAsPrimes);
        run("keepsDecadeStyleApostropheWithLetterFlankLatin", QuoteClassificationEngineTest.keepsDecadeStyleApostropheWithLetterFlankLatin);
        TestTraceRecorder.flushClass("QuoteClassificationEngineTest");
        run("adjacentInlineObjectBoundariesMergingAndConflicts",
            org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.adjacentInlineObjectBoundariesMergingAndConflicts);
        run("centeredPunctBeforeAttachedReferenceKeepsLeadingGlueOnly",
            org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.centeredPunctBeforeAttachedReferenceKeepsLeadingGlueOnly);
        run("conflictingOpenTypeFeaturesThrows", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.conflictingOpenTypeFeaturesThrows);
        run("containingItemsAndFirstContainedItemBranches",
            org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.containingItemsAndFirstContainedItemBranches);
        run("dynamicShapingEmphasisItalicAtAndZeroPairedCapacityBranches",
            org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.dynamicShapingEmphasisItalicAtAndZeroPairedCapacityBranches);
        run("dynamicShapingTriggersAndEmphasisItalic", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.dynamicShapingTriggersAndEmphasisItalic);
        run("lineLengthGridBodyAlignmentBranches", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.lineLengthGridBodyAlignmentBranches);
        run("lruCacheUpdateExistingKeyAndClear", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.lruCacheUpdateExistingKeyAndClear);
        run("pairedPunctuationWithZeroCapacity", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.pairedPunctuationWithZeroCapacity);
        run("prepareWidthIndependentAnnotationBranches",
            org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.prepareWidthIndependentAnnotationBranches);
        run("rubySpreadAccumulationAndEdges", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.rubySpreadAccumulationAndEdges);
        run("rubySpreadSecondVisitAndZeroFirstCluster", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.rubySpreadSecondVisitAndZeroFirstCluster);
        run("shrinkOpportunitiesCoverAllPunctuationClassesAndSpaces",
            org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.shrinkOpportunitiesCoverAllPunctuationClassesAndSpaces);
        run("styleAtAndEmphasisItalicAtAndDynamicShapingBranches",
            org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.styleAtAndEmphasisItalicAtAndDynamicShapingBranches);
        run("verbatimRangesAndAutoSpaceDecisions", org.tiqian.layout.WidthIndependentAnnotationCacheCoverageTest.verbatimRangesAndAutoSpaceDecisions);
        TestTraceRecorder.flushClass("WidthIndependentAnnotationCacheCoverageTest");
        run("lineBoundaryClosesOneUlpGapWithoutChangingBaselineDistance",
            org.tiqian.layout.InlineObjectLayoutTest.lineBoundaryClosesOneUlpGapWithoutChangingBaselineDistance);
        run("inlineObjectUsesExistingInterlineSpaceWithoutMovingBaselines",
            org.tiqian.layout.InlineObjectLayoutTest.inlineObjectUsesExistingInterlineSpaceWithoutMovingBaselines);
        run("inlineObjectExpandsBaselineGapOnlyForActualCollision",
            org.tiqian.layout.InlineObjectLayoutTest.inlineObjectExpandsBaselineGapOnlyForActualCollision);
        run("inlineObjectSkipsFontShapingAndExpandsItsOwnLineMetrics",
            org.tiqian.layout.InlineObjectLayoutTest.inlineObjectSkipsFontShapingAndExpandsItsOwnLineMetrics);
        run("inlineObjectIsOneIndivisibleBreakCluster", org.tiqian.layout.InlineObjectLayoutTest.inlineObjectIsOneIndivisibleBreakCluster);
        run("inlineObjectKeepsAlternateSourceTextWhileSkippingItsGlyphShaping",
            org.tiqian.layout.InlineObjectLayoutTest.inlineObjectKeepsAlternateSourceTextWhileSkippingItsGlyphShaping);
        run("formulaBoundaryCompressionPushesAttachedCommaIntoPreviousLine",
            org.tiqian.layout.InlineObjectLayoutTest.formulaBoundaryCompressionPushesAttachedCommaIntoPreviousLine);
        run("adjustBreakForUnbreakablesRetreatsPastTheWholeContiguousRun",
            org.tiqian.layout.InlineObjectLayoutTest.adjustBreakForUnbreakablesRetreatsPastTheWholeContiguousRun);
        run("perAtomFormulaChainNeverBreaksMidRun", org.tiqian.layout.InlineObjectLayoutTest.perAtomFormulaChainNeverBreaksMidRun);
        run("punctuationAttachedToInlineObjectNeverStartsWrappedLine",
            org.tiqian.layout.InlineObjectLayoutTest.punctuationAttachedToInlineObjectNeverStartsWrappedLine);
        run("separatorSpaceBeforePunctuationCollapsesAndStaysWithInlineObject",
            org.tiqian.layout.InlineObjectLayoutTest.separatorSpaceBeforePunctuationCollapsesAndStaysWithInlineObject);
        run("relationStretchMovesBothFormulaSidesByTheSameFinalGeometry",
            org.tiqian.layout.InlineObjectLayoutTest.relationStretchMovesBothFormulaSidesByTheSameFinalGeometry);
        run("formulaBreakKeepsBaselineOperatorOnPreviousLine", org.tiqian.layout.InlineObjectLayoutTest.formulaBreakKeepsBaselineOperatorOnPreviousLine);
        TestTraceRecorder.flushClass("InlineObjectLayoutTest");
        run("plainParagraphEvidenceIsAppendOnly", org.tiqian.layout.PreparedParagraphRenderEvidenceTest.plainParagraphEvidenceIsAppendOnly);
        run("pinyinRubyEmitsRubyDecisions", org.tiqian.layout.PreparedParagraphRenderEvidenceTest.pinyinRubyEmitsRubyDecisions);
        run("bopomofoRubyEmitsBopomofoDecisions", org.tiqian.layout.PreparedParagraphRenderEvidenceTest.bopomofoRubyEmitsBopomofoDecisions);
        run("decorationsEmitSegmentsDotsAndRanges", org.tiqian.layout.PreparedParagraphRenderEvidenceTest.decorationsEmitSegmentsDotsAndRanges);
        run("styleDeltaEmitsPerCellStyleBlock", org.tiqian.layout.PreparedParagraphRenderEvidenceTest.styleDeltaEmitsPerCellStyleBlock);
        run("inlineBoxesEmitInlineEdges", org.tiqian.layout.PreparedParagraphRenderEvidenceTest.inlineBoxesEmitInlineEdges);
        TestTraceRecorder.flushClass("PreparedParagraphRenderEvidenceTest");

        run("appliesAdjacentPunctuationCompressionToDrawableGeometry",
            org.tiqian.layout.PunctuationGeometryEngineTest.appliesAdjacentPunctuationCompressionToDrawableGeometry);
        run("buildsTwoEmPunctuationAtomForRecommendedDashCodepoint",
            org.tiqian.layout.PunctuationGeometryEngineTest.buildsTwoEmPunctuationAtomForRecommendedDashCodepoint);
        run("compressesAdjacentCjkSingleQuoteCommaSequence", org.tiqian.layout.PunctuationGeometryEngineTest.compressesAdjacentCjkSingleQuoteCommaSequence);
        run("compressesCjkClosingBeforeAsciiPointMarkWithoutReclassifyingAscii",
            org.tiqian.layout.PunctuationGeometryEngineTest.compressesCjkClosingBeforeAsciiPointMarkWithoutReclassifyingAscii);
        run("gbFixedSeparatorsAreHalfWidthAndUnadjustable", org.tiqian.layout.PunctuationGeometryEngineTest.gbFixedSeparatorsAreHalfWidthAndUnadjustable);
        run("haltAdvanceFromShaperDrivesPunctuationBodyEndToEnd",
            org.tiqian.layout.PunctuationGeometryEngineTest.haltAdvanceFromShaperDrivesPunctuationBodyEndToEnd);
        run("inkBoundsDetermineCompressionAmountAndSides", org.tiqian.layout.PunctuationGeometryEngineTest.inkBoundsDetermineCompressionAmountAndSides);
        run("kaimingStyleHalvesInteriorPunctuationButNotSentenceEnd",
            org.tiqian.layout.PunctuationGeometryEngineTest.kaimingStyleHalvesInteriorPunctuationButNotSentenceEnd);
        run("inlineStopCompressionKnobLimitsPushInCapacity", org.tiqian.layout.PunctuationGeometryEngineTest.inlineStopCompressionKnobLimitsPushInCapacity);
        run("lineStartLenticularBracketConsumesOpeningGlue", org.tiqian.layout.PunctuationGeometryEngineTest.lineStartLenticularBracketConsumesOpeningGlue);
        run("looseLineEndStyleKeepsFullWidthPunctuation", org.tiqian.layout.PunctuationGeometryEngineTest.looseLineEndStyleKeepsFullWidthPunctuation);
        run("pushInConsumesWordSpaceBeforeMidLinePunctGlue", org.tiqian.layout.PunctuationGeometryEngineTest.pushInConsumesWordSpaceBeforeMidLinePunctGlue);
        run("pushInDrainsBracketOuterGlueBeforeInlineComma", org.tiqian.layout.PunctuationGeometryEngineTest.pushInDrainsBracketOuterGlueBeforeInlineComma);
        run("pushInKeepsFontCenteredPunctuationCompressionPaired",
            org.tiqian.layout.PunctuationGeometryEngineTest.pushInKeepsFontCenteredPunctuationCompressionPaired);
        run("recordsInkCalibratedPunctuationGeometryInLayoutDebug",
            org.tiqian.layout.PunctuationGeometryEngineTest.recordsInkCalibratedPunctuationGeometryInLayoutDebug);
        run("recordsPunctuationAtomsInLayoutDebug", org.tiqian.layout.PunctuationGeometryEngineTest.recordsPunctuationAtomsInLayoutDebug);
        run("shortHyphenConnectorIsHalfWidthWavyTildeFullWidth",
            org.tiqian.layout.PunctuationGeometryEngineTest.shortHyphenConnectorIsHalfWidthWavyTildeFullWidth);
        run("sinoWesternGapKnobDisablesStretchAndShrink", org.tiqian.layout.PunctuationGeometryEngineTest.sinoWesternGapKnobDisablesStretchAndShrink);
        run("sinoWesternGapShrinkFloorsAtEighthEm", org.tiqian.layout.PunctuationGeometryEngineTest.sinoWesternGapShrinkFloorsAtEighthEm);
        run("traditionalProfileCentresPauseStopGlueOnBothSides",
            org.tiqian.layout.PunctuationGeometryEngineTest.traditionalProfileCentresPauseStopGlueOnBothSides);
        TestTraceRecorder.flushClass("PunctuationGeometryEngineTest");
        run("autoSpaceDigitModeIsWiredIndependentlyOfLetterMode",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.autoSpaceDigitModeIsWiredIndependentlyOfLetterMode);
        run("autoSpaceDoesNotShrinkSpacesBetweenLatinWords", org.tiqian.layout.SpacingAndLineGeometryEngineTest.autoSpaceDoesNotShrinkSpacesBetweenLatinWords);
        run("autoSpaceDisabledKeepsTypedSpacesAtHalfEm", org.tiqian.layout.SpacingAndLineGeometryEngineTest.autoSpaceDisabledKeepsTypedSpacesAtHalfEm);
        run("autoSpaceGapAtLineEndIsTrimmedLikeAnyLineEdgeBlank",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.autoSpaceGapAtLineEndIsTrimmedLikeAnyLineEdgeBlank);
        run("autoSpaceReplacesTypedSpaceAtCjkLatinBoundary", org.tiqian.layout.SpacingAndLineGeometryEngineTest.autoSpaceReplacesTypedSpaceAtCjkLatinBoundary);
        run("blockIndentInsetsEveryLine", org.tiqian.layout.SpacingAndLineGeometryEngineTest.blockIndentInsetsEveryLine);
        run("emphasisDotGapIsExplicitAndIndependentOfLineHeight",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.emphasisDotGapIsExplicitAndIndependentOfLineHeight);
        run("emphasisSpanProducesDotAnchorsForHanAndSkipsPunctuation",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.emphasisSpanProducesDotAnchorsForHanAndSkipsPunctuation);
        run("firstLineIndentAdaptsToMeasureAndCanBeOverridden",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.firstLineIndentAdaptsToMeasureAndCanBeOverridden);
        run("firstLineIndentShrinksFirstLineMeasureOnly", org.tiqian.layout.SpacingAndLineGeometryEngineTest.firstLineIndentShrinksFirstLineMeasureOnly);
        run("halfEmWordSpacesDoNotStretchUnderJustification",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.halfEmWordSpacesDoNotStretchUnderJustification);
        run("hangingIndentFlushesFirstLineAndInsetsRest", org.tiqian.layout.SpacingAndLineGeometryEngineTest.hangingIndentFlushesFirstLineAndInsetsRest);
        run("interlinearLinesGetPerItemSegmentsWithAdjacentShortening",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.interlinearLinesGetPerItemSegmentsWithAdjacentShortening);
        run("interlinearMarksRaiseAutoLineHeightToSpacingFloor",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.interlinearMarksRaiseAutoLineHeightToSpacingFloor);
        run("justifyFillsSaturatedLineWithUncappedEvenShare",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.justifyFillsSaturatedLineWithUncappedEvenShare);
        run("justifyStretchesPunctuationLatinBoundaryInTierThree",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.justifyStretchesPunctuationLatinBoundaryInTierThree);
        run("lineLengthGridCanBeBypassedForExactWidths", org.tiqian.layout.SpacingAndLineGeometryEngineTest.lineLengthGridCanBeBypassedForExactWidths);
        run("lineLengthGridFloorsMeasureToWholeCharsAndOffsetsBody",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.lineLengthGridFloorsMeasureToWholeCharsAndOffsetsBody);
        run("mourningSpanIsKeptUnbrokenAndFramedPerLine", org.tiqian.layout.SpacingAndLineGeometryEngineTest.mourningSpanIsKeptUnbrokenAndFramedPerLine);
        run("mourningSpanWiderThanMeasureSplitsWithOpenEdges",
            org.tiqian.layout.SpacingAndLineGeometryEngineTest.mourningSpanWiderThanMeasureSplitsWithOpenEdges);
        run("usesFontDeclaredTypoBoxForCjkLineBox", org.tiqian.layout.SpacingAndLineGeometryEngineTest.usesFontDeclaredTypoBoxForCjkLineBox);
        TestTraceRecorder.flushClass("SpacingAndLineGeometryEngineTest");
        run("recordedEvidenceLayoutMatchesGolden", RecordedEvidenceGoldenParityTest.recordedEvidenceLayoutMatchesGolden);
        TestTraceRecorder.flushClass("RecordedEvidenceGoldenParityTest");

        run("emphasisDotGapEmMustBeFiniteAndNonNegative",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.emphasisDotGapEmMustBeFiniteAndNonNegative);
        run("inlineObjectMinimumClearanceEmMustBeFiniteAndNonNegative",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineObjectMinimumClearanceEmMustBeFiniteAndNonNegative);
        run("sourceTextMustNotContainUnpairedSurrogates",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.sourceTextMustNotContainUnpairedSurrogates);
        run("inlineBoxSpanMustBeANonEmptyInBoundsRange",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineBoxSpanMustBeANonEmptyInBoundsRange);
        run("inlineBoxSpanMustHaveFiniteInlineEdges", org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineBoxSpanMustHaveFiniteInlineEdges);
        run("lineBreakSpansMustBeNonEmptyInBoundsRanges",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.lineBreakSpansMustBeNonEmptyInBoundsRanges);
        run("autoSpaceSuppressedRangesMustBeNonEmptyInBounds",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.autoSpaceSuppressedRangesMustBeNonEmptyInBounds);
        run("inlineObjectRangesMustBeUnique", org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineObjectRangesMustBeUnique);
        run("inlineObjectRangesMustNotOverlap", org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineObjectRangesMustNotOverlap);
        run("inlineObjectMustCoverANonEmptyInBoundsRange",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineObjectMustCoverANonEmptyInBoundsRange);
        run("inlineObjectMustHaveFinitePositiveGeometry",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineObjectMustHaveFinitePositiveGeometry);
        run("inlineObjectLeadingBoundaryMustBeFixed", org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineObjectLeadingBoundaryMustBeFixed);
        run("inlineObjectTrailingBoundaryMustNotExceedAdvance",
            org.tiqian.layout.ParagraphLayoutEngineValidationCoverageTest.inlineObjectTrailingBoundaryMustNotExceedAdvance);
        TestTraceRecorder.flushClass("ParagraphLayoutEngineValidationCoverageTest");
        run("returnsDebuggableSingleLineResult", ExplainableStubParagraphLayoutEngineTest.returnsDebuggableSingleLineResult);
        run("recordsInjectedLineBreakerStrategyInDebugDecisions", ExplainableStubParagraphLayoutEngineTest.recordsInjectedLineBreakerStrategyInDebugDecisions);
        run("mandatoryLineBreakClustersAreZeroWidthAndNotShaped", ExplainableStubParagraphLayoutEngineTest.mandatoryLineBreakClustersAreZeroWidthAndNotShaped);
        run("consecutiveMandatoryLineBreaksCreateOneEmptyLineBox",
            ExplainableStubParagraphLayoutEngineTest.consecutiveMandatoryLineBreaksCreateOneEmptyLineBox);
        run("singleMandatoryBreakAfterWrappedLineDoesNotCreateEmptyLine",
            ExplainableStubParagraphLayoutEngineTest.singleMandatoryBreakAfterWrappedLineDoesNotCreateEmptyLine);
        run("crlfIsOneMandatoryBreakCluster", ExplainableStubParagraphLayoutEngineTest.crlfIsOneMandatoryBreakCluster);
        run("consecutiveAndTrailingMandatoryBreaksPreserveBlankLines",
            ExplainableStubParagraphLayoutEngineTest.consecutiveAndTrailingMandatoryBreaksPreserveBlankLines);
        run("mandatoryBreakLineIsNotJustified", ExplainableStubParagraphLayoutEngineTest.mandatoryBreakLineIsNotJustified);
        run("rejectsShaperClustersThatDoNotCoverFontDecisionRange",
            ExplainableStubParagraphLayoutEngineTest.rejectsShaperClustersThatDoNotCoverFontDecisionRange);
        run("preservesShaperGlyphBoundsInLayoutGlyphRuns", ExplainableStubParagraphLayoutEngineTest.preservesShaperGlyphBoundsInLayoutGlyphRuns);
        run("recordsFallbackDecisionsPerCluster", ExplainableStubParagraphLayoutEngineTest.recordsFallbackDecisionsPerCluster);
        run("combiningMarksStayInTheirBaseShapingRuns", ExplainableStubParagraphLayoutEngineTest.combiningMarksStayInTheirBaseShapingRuns);
        run("complexEmojiGraphemesStayAtomicAcrossGeometryOnlyBoundaries",
            ExplainableStubParagraphLayoutEngineTest.complexEmojiGraphemesStayAtomicAcrossGeometryOnlyBoundaries);
        run("complexEmojiSequencesReachTheShaperAsCompleteEmojiRanges",
            ExplainableStubParagraphLayoutEngineTest.complexEmojiSequencesReachTheShaperAsCompleteEmojiRanges);
        run("emojiRoleMatrixSeparatesSupportedSequencesFromAdjacentAndUnrelatedText",
            ExplainableStubParagraphLayoutEngineTest.emojiRoleMatrixSeparatesSupportedSequencesFromAdjacentAndUnrelatedText);
        run("sourceGraphemeBoundariesDoNotJoinZwJWithOrdinaryText",
            ExplainableStubParagraphLayoutEngineTest.sourceGraphemeBoundariesDoNotJoinZwJWithOrdinaryText);
        run("recordsUnicodeEmojiSequenceRolePromotions", ExplainableStubParagraphLayoutEngineTest.recordsUnicodeEmojiSequenceRolePromotions);
        run("complexEmojiGraphemesHonorTextSpanStyleBoundaries", ExplainableStubParagraphLayoutEngineTest.complexEmojiGraphemesHonorTextSpanStyleBoundaries);
        TestTraceRecorder.flushClass("ExplainableStubParagraphLayoutEngineTest");
        run("connectorBoundariesAvoidStretchUnderJustification", JustifierEngineTest.connectorBoundariesAvoidStretchUnderJustification);
        run("inseparableNumberAndUnitBoundaryAvoidsStretchUnderJustification",
            JustifierEngineTest.inseparableNumberAndUnitBoundaryAvoidsStretchUnderJustification);
        run("lastLineAlignmentPositionsTheLastLineViaIndent", JustifierEngineTest.lastLineAlignmentPositionsTheLastLineViaIndent);
        run("mandatoryBreakLinesTakeLastLineAlignment", JustifierEngineTest.mandatoryBreakLinesTakeLastLineAlignment);
        run("lastLineIsNeverJustified", JustifierEngineTest.lastLineIsNeverJustified);
        run("latinGlyphPositionsSurviveAutospaceAndJustification", JustifierEngineTest.latinGlyphPositionsSurviveAutospaceAndJustification);
        run("justifiesNonLastLineUsingCjkInterCharGapsAsLastResort", JustifierEngineTest.justifiesNonLastLineUsingCjkInterCharGapsAsLastResort);
        run("usesPunctuationGlueFirstWhenDeficitMatchesCompression", JustifierEngineTest.usesPunctuationGlueFirstWhenDeficitMatchesCompression);
        run("justifyDistributesDeficitAcrossPriorityChain", JustifierEngineTest.justifyDistributesDeficitAcrossPriorityChain);
        run("cjkInterCharActsAsLastResortWhenPunctGlueExhausted", JustifierEngineTest.cjkInterCharActsAsLastResortWhenPunctGlueExhausted);
        run("uniformTrackingIncludesBracketInnerSides", JustifierEngineTest.uniformTrackingIncludesBracketInnerSides);
        run("bracketWesternInteriorStretchesInTierThreeNotTierTwo", JustifierEngineTest.bracketWesternInteriorStretchesInTierThreeNotTierTwo);
        run("dashBoundariesDoNotReceiveUniformTracking", JustifierEngineTest.dashBoundariesDoNotReceiveUniformTracking);
        run("typedSinoWesternSpacesStretchInTierTwo", JustifierEngineTest.typedSinoWesternSpacesStretchInTierTwo);
        run("punctuationToWesternBoundaryStretchesInTierThree", JustifierEngineTest.punctuationToWesternBoundaryStretchesInTierThree);
        run("lineEdgeSinoWesternSpaceStaysCollapsed", JustifierEngineTest.lineEdgeSinoWesternSpaceStaysCollapsed);
        TestTraceRecorder.flushClass("JustifierEngineTest");
    }
}
