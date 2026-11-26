package org.tiqian.layout;

using org.tiqian.layout.ProgressiveBreakTierPriority;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.AccurateSum;
import org.tiqian.core.TextRange;
import org.tiqian.core.BreakOpportunityDecisionInfo;
import org.tiqian.core.LineBreakPolicy;
import org.tiqian.core.SourceInteractionBoundaries;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.linebreak.Hyphenator;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;

/**
 * `LatinSegmentCuts`: the break offsets that `LatinSegmentBreakPlanner.plan` computes for one
 * segment. `allCuts` holds every offset in ascending order without duplicates; `hyphenCuts` holds
 * the subset that inserts a hyphen when the line breaks there.
 */
class LatinSegmentCuts {
    public final allCuts:Array<Int>;
    public final hyphenCuts:Array<Int>;

    public function new(allCuts:Array<Int>, hyphenCuts:Array<Int>) {
        this.allCuts = allCuts;
        this.hyphenCuts = hyphenCuts;
    }
}

/**
 * `LatinSegmentBreakPlanner`: the break-offset computation of `ParagraphShapingSession.run` for
 * one shaped segment: progressive technical tiers (structural, syllable, emergency, whole token),
 * Latin hyphenation, separator cuts and opaque hard cuts. It shapes candidate pieces and records
 * break-opportunity, emergency-tracking and progressive-break decisions through the session's
 * public methods, so the session keeps every collected value. Each method copies the fields it
 * reads into locals first, for the reason given in the `ParagraphShapingSession` comment.
 */
class LatinSegmentBreakPlanner {
    final session:ParagraphShapingSession;
    final hyphenator:Hyphenator;
    final input:LayoutInput;
    final text:String;
    final measure:Float;

    public function new(session:ParagraphShapingSession, hyphenator:Hyphenator, input:LayoutInput, text:String, measure:Float) {
        this.session = session;
        this.hyphenator = hyphenator;
        this.input = input;
        this.text = text;
        this.measure = measure;
    }


    /** The break offsets of `segmentRange`, shaped with `decision` as `shaped`. */
    public function plan(decision:FontDecision, segmentRange:TextRange, shaped:ShapingResult):LatinSegmentCuts {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final session = this.session;
        final hyphenator = this.hyphenator;
        final input = this.input;
        final text = this.text;
        final measure = this.measure;
        final isLatin = decision.role == FontRole.LatinText && segmentRange.length > 0;
        final w = isLatin ? text.substring(segmentRange.start, segmentRange.end) : "";

        var progressiveSpan:Null<org.tiqian.core.LineBreakSpan> = null;
        for (sIdx in 0...input.content.lineBreakSpans.length) {
            final s = input.content.lineBreakSpans[sIdx];
            if (s.policy == LineBreakPolicy.ProgressiveTechnical
                && segmentRange.start >= s.range.start
                && segmentRange.end <= s.range.end) {
                progressiveSpan = s;
                break;
            }
        }

        var allLetters = isLatin && w.length > 0;
        if (isLatin) {
            for (cIdx in 0...w.length) {
                if (!ParagraphShapingStage.isLetter(w.charCodeAt(cIdx))) {
                    allLetters = false;
                    break;
                }
            }
        }

        var isAllCaps = allLetters && w.length >= 2;
        if (isAllCaps) {
            for (cIdx in 0...w.length) {
                if (ParagraphShapingStage.isLowerCase(w.charCodeAt(cIdx))) {
                    isAllCaps = false;
                    break;
                }
            }
        }
        final isAbbreviation = isAllCaps && w.length < ParagraphShapingStage.LATIN_OPAQUE_TOKEN_MIN_LENGTH;
        var hasInternalUpper = false;
        if (allLetters && !isAllCaps && !isAbbreviation) {
            for (cIdx in 1...w.length) {
                if (ParagraphShapingStage.isUpperCase(w.charCodeAt(cIdx))) {
                    hasInternalUpper = true;
                    break;
                }
            }
        }
        final isCamelCase = allLetters && !isAllCaps && !isAbbreviation && hasInternalUpper;

        final tokenTerms:Array<Float> = [];
        for (clIdx in 0...shaped.clusters.length) {
            tokenTerms.push(shaped.clusters[clIdx].advance);
        }
        final tokenAdvance = AccurateSum.of(tokenTerms);
        final strongReason = isLatin ? ParagraphShapingStage.strongNonLexicalReason(w) : null;

        var syllableCuts = new Array<Int>();
        if (allLetters && !isAbbreviation && !isCamelCase && w.indexOf("-") < 0 && strongReason == null) {
            final hyphenPoints = hyphenator.hyphenate(w);
            final uniquePoints = new Array<Int>();
            for (p in 0...hyphenPoints.length) {
                final pt = hyphenPoints[p];
                var exists = false;
                for (q in 0...uniquePoints.length) {
                    if (uniquePoints[q] == pt) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    uniquePoints.push(pt);
            }
            ParagraphShapingStage.sortInts(uniquePoints);
            syllableCuts = uniquePoints;
        }

        var longestUnhyphenatedLetterPiece = 0;
        if (allLetters) {
            final bounds = [0];
            for (p in 0...syllableCuts.length)
                bounds.push(syllableCuts[p]);
            bounds.push(w.length);
            var maxLen = 0;
            for (p in 0...(bounds.length - 1)) {
                final diff = bounds[p + 1] - bounds[p];
                if (diff > maxLen)
                    maxLen = diff;
            }
            longestUnhyphenatedLetterPiece = maxLen;
        }

        final isLongUnhyphenatedLetterToken = allLetters
            && !isAbbreviation
            && !isCamelCase
            && longestUnhyphenatedLetterPiece >= ParagraphShapingStage.LATIN_OPAQUE_TOKEN_MIN_LENGTH;
        final isLongOpaqueLatinToken = strongReason != null
            || isLongUnhyphenatedLetterToken
            || (isLatin && !allLetters && w.length >= ParagraphShapingStage.LATIN_OPAQUE_TOKEN_MIN_LENGTH);

        var technicalStructuralCuts = new Array<Int>();
        if (progressiveSpan != null && isLatin) {
            final cutsSet = new Array<Int>();
            final cc = ParagraphShapingStage.camelCaseCuts(text, segmentRange);
            for (c in 0...cc.length)
                cutsSet.push(cc[c]);
            final at = ParagraphShapingStage.alphaNumericTransitionCuts(text, segmentRange);
            for (c in 0...at.length) {
                final v = at[c];
                var exists = false;
                for (q in 0...cutsSet.length) {
                    if (cutsSet[q] == v) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    cutsSet.push(v);
            }
            for (i in 0...(w.length - 1)) {
                if (ParagraphShapingStage.isProgressiveTechnicalBreakAfterChar(w.charCodeAt(i))) {
                    final v = segmentRange.start + i + 1;
                    var exists = false;
                    for (q in 0...cutsSet.length) {
                        if (cutsSet[q] == v) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists)
                        cutsSet.push(v);
                }
            }
            ParagraphShapingStage.sortInts(cutsSet);
            technicalStructuralCuts = cutsSet;
        }

        var rawTechnicalSyllableCuts = new Array<Int>();
        if (progressiveSpan != null && isLatin) {
            final preferredBounds = [segmentRange.start];
            for (c in 0...technicalStructuralCuts.length)
                preferredBounds.push(technicalStructuralCuts[c]);
            preferredBounds.push(segmentRange.end);
            final uniqueBounds = new Array<Int>();
            for (p in 0...preferredBounds.length) {
                final pt = preferredBounds[p];
                var exists = false;
                for (q in 0...uniqueBounds.length) {
                    if (uniqueBounds[q] == pt) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    uniqueBounds.push(pt);
            }
            ParagraphShapingStage.sortInts(uniqueBounds);

            final cutsList = new Array<Int>();
            for (p in 0...(uniqueBounds.length - 1)) {
                final pieceStart = uniqueBounds[p];
                final pieceEnd = uniqueBounds[p + 1];
                final piece = text.substring(pieceStart, pieceEnd);
                if (ParagraphShapingStage.strongNonLexicalReason(piece) != null)
                    continue;
                var runStart = pieceStart;
                while (runStart < pieceEnd) {
                    while (runStart < pieceEnd && !ParagraphShapingStage.isLetter(text.charCodeAt(runStart)))
                        runStart++;
                    var runEnd = runStart;
                    while (runEnd < pieceEnd && ParagraphShapingStage.isLetter(text.charCodeAt(runEnd)))
                        runEnd++;
                    if (runEnd > runStart) {
                        final word = text.substring(runStart, runEnd);
                        final wordHyphs = hyphenator.hyphenate(word);
                        for (h in 0...wordHyphs.length) {
                            final off = wordHyphs[h];
                            if (off >= 1 && off < word.length) {
                                cutsList.push(runStart + off);
                            }
                        }
                    }
                    runStart = runEnd > runStart ? runEnd : (runStart + 1);
                }
            }
            final uniqueCuts = new Array<Int>();
            for (p in 0...cutsList.length) {
                final pt = cutsList[p];
                var exists = false;
                for (q in 0...uniqueCuts.length) {
                    if (uniqueCuts[q] == pt) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    uniqueCuts.push(pt);
            }
            ParagraphShapingStage.sortInts(uniqueCuts);
            rawTechnicalSyllableCuts = uniqueCuts;
        }

        final technicalSyllableCuts = new Array<Int>();
        for (i in 0...rawTechnicalSyllableCuts.length) {
            final cut = rawTechnicalSyllableCuts[i];
            var inStructural = false;
            for (j in 0...technicalStructuralCuts.length) {
                if (technicalStructuralCuts[j] == cut) {
                    inStructural = true;
                    break;
                }
            }
            if (!inStructural) {
                technicalSyllableCuts.push(cut);
            }
        }

        var technicalEmergencyCuts = new Array<Int>();
        if (progressiveSpan != null && isLatin) {
            final rejectedTiers = session.getRejectedTiers(progressiveSpan.range);
            final exposedForCurrentLine = rejectedTiers != null && rejectedTiers.size() > 0;
            final preferredBounds = [segmentRange.start];
            for (c in 0...technicalStructuralCuts.length)
                preferredBounds.push(technicalStructuralCuts[c]);
            for (c in 0...technicalSyllableCuts.length)
                preferredBounds.push(technicalSyllableCuts[c]);
            preferredBounds.push(segmentRange.end);
            final uniqueBounds = new Array<Int>();
            for (p in 0...preferredBounds.length) {
                final pt = preferredBounds[p];
                var exists = false;
                for (q in 0...uniqueBounds.length) {
                    if (uniqueBounds[q] == pt) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    uniqueBounds.push(pt);
            }
            ParagraphShapingStage.sortInts(uniqueBounds);

            final interiorEmergencyCuts = new Array<Int>();
            for (p in 0...(uniqueBounds.length - 1)) {
                final pStart = uniqueBounds[p];
                final pEnd = uniqueBounds[p + 1];
                final pieceRange = new TextRange(pStart, pEnd);
                final pieceShaped = session.shapeSegment(decision, pieceRange);
                final pieceTerms:Array<Float> = [];
                for (clIdx in 0...pieceShaped.clusters.length) {
                    pieceTerms.push(pieceShaped.clusters[clIdx].advance);
                }
                final pieceAdvance = AccurateSum.of(pieceTerms);
                if (!exposedForCurrentLine
                    && pieceAdvance <= measure
                    && session.progressiveSpanAdvance(progressiveSpan.range) <= measure) {
                    // nothing
                } else {
                    final graphemes = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, pieceRange);
                    for (g in 0...graphemes.length) {
                        final pt = graphemes[g];
                        if (pt > pStart && pt < pEnd) {
                            interiorEmergencyCuts.push(pt);
                        }
                    }
                }
            }
            final rejectedCleanBoundaries = new Array<Int>();
            if (rejectedTiers != null) {
                if (rejectedTiers.has(ProgressiveBreakTier.Structural.priority())) {
                    for (c in 0...technicalStructuralCuts.length)
                        rejectedCleanBoundaries.push(technicalStructuralCuts[c]);
                }
                if (rejectedTiers.has(ProgressiveBreakTier.Syllable.priority())) {
                    for (c in 0...technicalSyllableCuts.length)
                        rejectedCleanBoundaries.push(technicalSyllableCuts[c]);
                }
            }
            final combined = new Array<Int>();
            for (c in 0...interiorEmergencyCuts.length)
                combined.push(interiorEmergencyCuts[c]);
            for (c in 0...rejectedCleanBoundaries.length)
                combined.push(rejectedCleanBoundaries[c]);
            final uniqueCombined = new Array<Int>();
            for (p in 0...combined.length) {
                final pt = combined[p];
                var exists = false;
                for (q in 0...uniqueCombined.length) {
                    if (uniqueCombined[q] == pt) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    uniqueCombined.push(pt);
            }
            ParagraphShapingStage.sortInts(uniqueCombined);
            technicalEmergencyCuts = uniqueCombined;
        }

        if (progressiveSpan != null) {
            if (technicalEmergencyCuts.length > 0) {
                final rej = session.getRejectedTiers(progressiveSpan.range);
                var reason = "ProgressiveTechnicalSpan";
                if (rej != null && rej.size() > 0) {
                    final tiers = new Array<Int>();
                    for (i in 0...rej.size())
                        tiers.push(rej.at(i));
                    var tIdx = 1;
                    while (tIdx < tiers.length) {
                        final curr = tiers[tIdx];
                        var j = tIdx - 1;
                        while (j >= 0 && tiers[j] > curr) {
                            tiers[j + 1] = tiers[j];
                            j--;
                        }
                        tiers[j + 1] = curr;
                        tIdx++;
                    }
                    var joined = "";
                    for (i in 0...tiers.length) {
                        if (i > 0)
                            joined += "+";
                        joined += ParagraphShapingStage.tierName(ProgressiveBreakTierPriority.fromPriority(tiers[i]));
                    }
                    reason = "CurrentLineTechnicalTierRejection:" + joined;
                }
                session.registerEmergencyTrackingEligibility(progressiveSpan.range, reason);
            }

            final tierArrays = [technicalStructuralCuts, technicalSyllableCuts, technicalEmergencyCuts];
            final tierTypes = [
                ProgressiveBreakTier.Structural,
                ProgressiveBreakTier.Syllable,
                ProgressiveBreakTier.Emergency
            ];
            for (tIdx in 0...3) {
                final tier = tierTypes[tIdx];
                final offsets = tierArrays[tIdx];
                final rej = session.getRejectedTiers(progressiveSpan.range);
                if (rej != null && rej.has(tier.priority())) {
                    continue;
                }
                final uniqueOffsets = new Array<Int>();
                for (p in 0...offsets.length) {
                    final pt = offsets[p];
                    var exists = false;
                    for (q in 0...uniqueOffsets.length) {
                        if (uniqueOffsets[q] == pt) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists)
                        uniqueOffsets.push(pt);
                }
                ParagraphShapingStage.sortInts(uniqueOffsets);
                if (uniqueOffsets.length > 0) {
                    final rejNotEmpty = rej != null && rej.size() > 0;
                    final breakReason = (tier == ProgressiveBreakTier.Emergency
                        && rejNotEmpty) ? "CurrentLineTechnicalEmergencyBreak" : "ProgressiveTechnicalBreak";
                    session.recordBreakOpportunity(new BreakOpportunityDecisionInfo(segmentRange, w, ParagraphShapingStage.copyInts(uniqueOffsets), breakReason,
                        ParagraphShapingStage.tierName(tier)));
                }
                for (oIdx in 0...uniqueOffsets.length) {
                    final offset = uniqueOffsets[oIdx];
                    session.putProgressiveBreak(offset, new ProgressiveBreakOpportunity(tier, progressiveSpan.range));
                }
            }

            var boundaryTier = ProgressiveBreakTier.WholeToken;
            if (segmentRange.start > progressiveSpan.range.start && ParagraphShapingStage.isWhitespace(text.charCodeAt(segmentRange.start - 1))) {
                boundaryTier = ProgressiveBreakTier.Whitespace;
            }
            final rej = session.getRejectedTiers(progressiveSpan.range);
            if (rej == null || !rej.has(boundaryTier.priority())) {
                final wholeToken = new ProgressiveBreakOpportunity(boundaryTier, progressiveSpan.range);
                session.putProgressiveBreak(segmentRange.start, wholeToken);
                final wrapReason = boundaryTier == ProgressiveBreakTier.Whitespace ? "ProgressiveTechnicalWhitespaceBreak" : "ProgressiveTechnicalWholeTokenWrap";
                session.recordBreakOpportunity(new BreakOpportunityDecisionInfo(segmentRange, w, [segmentRange.start], wrapReason,
                    ParagraphShapingStage.tierName(boundaryTier)));
            }
        }

        var cleanCuts = new Array<Int>();
        if (progressiveSpan != null) {
            for (c in 0...technicalStructuralCuts.length)
                cleanCuts.push(technicalStructuralCuts[c]);
            for (c in 0...technicalSyllableCuts.length)
                cleanCuts.push(technicalSyllableCuts[c]);
            for (c in 0...technicalEmergencyCuts.length)
                cleanCuts.push(technicalEmergencyCuts[c]);
        } else if (!isLatin) {
            // empty
        } else if (w.indexOf("-") >= 0) {
            final existing = ParagraphShapingStage.existingHyphenCuts(text, segmentRange);
            for (c in 0...existing.length)
                cleanCuts.push(existing[c]);
            final sep = latinSeparatorCuts(segmentRange, tokenAdvance, isLongOpaqueLatinToken);
            for (c in 0...sep.length)
                cleanCuts.push(sep[c]);
        } else if (isCamelCase) {
            cleanCuts = ParagraphShapingStage.camelCaseCuts(text, segmentRange);
        } else if (!allLetters) {
            cleanCuts = latinSeparatorCuts(segmentRange, tokenAdvance, isLongOpaqueLatinToken);
        }

        var hyphenCuts = new Array<Int>();
        if (progressiveSpan == null && allLetters && !isAbbreviation && !isCamelCase && !isLongUnhyphenatedLetterToken && w.indexOf("-") < 0
            && cleanCuts.length == 0) {
            hyphenCuts = latinWordCuts(decision, segmentRange, syllableCuts);
        }

        var opaqueHardCuts = new Array<Int>();
        if (progressiveSpan == null
            && isLatin
            && (!allLetters || isLongUnhyphenatedLetterToken)
            && (tokenAdvance > measure || isLongOpaqueLatinToken)) {
            opaqueHardCuts = latinOpaqueHardCuts(decision, segmentRange, cleanCuts, isLongOpaqueLatinToken);
        }

        if (progressiveSpan == null && opaqueHardCuts.length > 0) {
            final cleanBounds = [segmentRange.start];
            for (c in 0...cleanCuts.length)
                cleanBounds.push(cleanCuts[c]);
            cleanBounds.push(segmentRange.end);
            final uniqueBounds = new Array<Int>();
            for (p in 0...cleanBounds.length) {
                final pt = cleanBounds[p];
                var exists = false;
                for (q in 0...uniqueBounds.length) {
                    if (uniqueBounds[q] == pt) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    uniqueBounds.push(pt);
            }
            ParagraphShapingStage.sortInts(uniqueBounds);

            for (p in 0...(uniqueBounds.length - 1)) {
                final pieceStart = uniqueBounds[p];
                final pieceEnd = uniqueBounds[p + 1];
                var hasPieceHardCuts = false;
                for (k in 0...opaqueHardCuts.length) {
                    final cut = opaqueHardCuts[k];
                    if (cut > pieceStart && cut < pieceEnd) {
                        hasPieceHardCuts = true;
                        break;
                    }
                }
                if (!hasPieceHardCuts)
                    continue;
                final pieceRange = new TextRange(pieceStart, pieceEnd);
                final pieceReason = ParagraphShapingStage.strongNonLexicalReason(text.substring(pieceStart, pieceEnd));
                if (pieceReason != null) {
                    session.registerEmergencyTrackingEligibility(pieceRange, pieceReason);
                }
            }
        }

        final allCutsCombined = new Array<Int>();
        for (c in 0...cleanCuts.length)
            allCutsCombined.push(cleanCuts[c]);
        for (c in 0...hyphenCuts.length)
            allCutsCombined.push(hyphenCuts[c]);
        for (c in 0...opaqueHardCuts.length)
            allCutsCombined.push(opaqueHardCuts[c]);

        final allCuts = new Array<Int>();
        for (p in 0...allCutsCombined.length) {
            final pt = allCutsCombined[p];
            var exists = false;
            for (q in 0...allCuts.length) {
                if (allCuts[q] == pt) {
                    exists = true;
                    break;
                }
            }
            if (!exists)
                allCuts.push(pt);
        }
        ParagraphShapingStage.sortInts(allCuts);
        return new LatinSegmentCuts(allCuts, hyphenCuts);
    }

    function latinWordCuts(decision:FontDecision, wordRange:TextRange, syllable:Array<Int>):Array<Int> {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final session = this.session;
        final measure = this.measure;
        final cuts = new Array<Int>();
        for (i in 0...syllable.length) {
            cuts.push(wordRange.start + syllable[i]);
        }
        final relBounds = [0];
        for (sIdx in 0...syllable.length) {
            final s = syllable[sIdx];
            var exists = false;
            for (j in 0...relBounds.length) {
                if (relBounds[j] == s) {
                    exists = true;
                    break;
                }
            }
            if (!exists)
                relBounds.push(s);
        }
        var lenExists = false;
        for (j in 0...relBounds.length) {
            if (relBounds[j] == wordRange.length) {
                lenExists = true;
                break;
            }
        }
        if (!lenExists)
            relBounds.push(wordRange.length);
        ParagraphShapingStage.sortInts(relBounds);

        for (i in 0...(relBounds.length - 1)) {
            final a = relBounds[i];
            final b = relBounds[i + 1];
            final pieceShaped = session.shapeSegment(decision, new TextRange(wordRange.start + a, wordRange.start + b));
            final pieceAdvance = pieceShaped.clusters.length == 1 ? pieceShaped.clusters[0].advance : 0.0;
            if (pieceAdvance <= measure)
                continue;
            final lo = a + ParagraphShapingStage.HYPHEN_MIN_LEFT;
            final hi = b - ParagraphShapingStage.HYPHEN_MIN_RIGHT;
            var off = lo <= hi ? lo : (a + 1);
            final endOff = lo <= hi ? (hi + 1) : b;
            while (off < endOff) {
                final c = wordRange.start + off;
                var exists = false;
                for (k in 0...cuts.length) {
                    if (cuts[k] == c) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    cuts.push(c);
                off++;
            }
        }
        ParagraphShapingStage.sortInts(cuts);
        return cuts;
    }

    function latinSeparatorCuts(tokenRange:TextRange, tokenAdvance:Float, forceOpaqueBreaks:Bool):Array<Int> {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final session = this.session;
        final text = this.text;
        final measure = this.measure;
        final token = text.substring(tokenRange.start, tokenRange.end);
        final urlLike = ParagraphShapingStage.isUrlLikeLatinToken(token);
        var opaque = false;
        for (i in 0...token.length) {
            if (!ParagraphShapingStage.isLetter(token.charCodeAt(i))) {
                opaque = true;
                break;
            }
        }
        final structuralSolidus = ParagraphShapingStage.hasBreakableLatinSolidus(token);
        final bibliographicLocatorCuts = ParagraphShapingStage.bibliographicNumericLocatorBreakOffsets(token);
        final opaqueSeparatorMode = urlLike || (opaque && (tokenAdvance > measure || forceOpaqueBreaks));
        if (!structuralSolidus && !opaqueSeparatorMode && bibliographicLocatorCuts.length == 0) {
            return [];
        }
        final cuts = new Array<Int>();
        for (i in 0...bibliographicLocatorCuts.length) {
            cuts.push(tokenRange.start + bibliographicLocatorCuts[i]);
        }
        if (bibliographicLocatorCuts.length > 0) {
            session.recordBreakOpportunity(new BreakOpportunityDecisionInfo(tokenRange, token, ParagraphShapingStage.copyInts(cuts), "BibliographicNumericLocatorBreak"));
        }
        for (i in 0...(token.length - 1)) {
            final breakAfter = (structuralSolidus && !urlLike && token.charCodeAt(i) == 47)
                || (opaqueSeparatorMode && ParagraphShapingStage.isLatinTokenBreakAfter(token, i, tokenAdvance <= measure));
            if (breakAfter) {
                cuts.push(tokenRange.start + i + 1);
            }
        }
        return cuts;
    }

    function latinOpaqueHardCuts(decision:FontDecision, tokenRange:TextRange, cleanCuts:Array<Int>, forceOpaqueBreaks:Bool):Array<Int> {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final session = this.session;
        final text = this.text;
        final measure = this.measure;
        final relBounds = [0];
        for (i in 0...cleanCuts.length) {
            final rel = cleanCuts[i] - tokenRange.start;
            var exists = false;
            for (j in 0...relBounds.length) {
                if (relBounds[j] == rel) {
                    exists = true;
                    break;
                }
            }
            if (!exists)
                relBounds.push(rel);
        }
        var lenExists = false;
        for (j in 0...relBounds.length) {
            if (relBounds[j] == tokenRange.length) {
                lenExists = true;
                break;
            }
        }
        if (!lenExists)
            relBounds.push(tokenRange.length);
        ParagraphShapingStage.sortInts(relBounds);

        final cuts = new Array<Int>();
        for (i in 0...(relBounds.length - 1)) {
            final a = relBounds[i];
            final b = relBounds[i + 1];
            if (b - a <= 1)
                continue;
            final pieceRange = new TextRange(tokenRange.start + a, tokenRange.start + b);
            final pieceShaped = session.shapeSegment(decision, pieceRange);
            final pieceAdvance = pieceShaped.clusters.length == 1 ? pieceShaped.clusters[0].advance : 0.0;
            if (pieceAdvance <= measure && !(forceOpaqueBreaks && (b - a) >= ParagraphShapingStage.LATIN_OPAQUE_TOKEN_MIN_LENGTH)) {
                continue;
            }
            final graphemes = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, pieceRange);
            for (g in 0...graphemes.length) {
                final pos = graphemes[g];
                if (pos > pieceRange.start && pos < pieceRange.end) {
                    var exists = false;
                    for (k in 0...cuts.length) {
                        if (cuts[k] == pos) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists)
                        cuts.push(pos);
                }
            }
        }
        ParagraphShapingStage.sortInts(cuts);
        return cuts;
    }

}
