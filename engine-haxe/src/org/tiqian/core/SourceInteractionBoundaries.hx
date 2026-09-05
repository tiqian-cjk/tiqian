package org.tiqian.core;

// CJK↔Western boundaries receive no automatic spacing. A boundary strictly inside a range

/** Source UTF-16 interaction boundaries for selection, hit testing, and spacing. */
class SourceInteractionBoundaries {
    private static final HIGH_SURROGATE_START:Int = 0xD800;
    private static final HIGH_SURROGATE_END:Int = 0xDBFF;
    private static final LOW_SURROGATE_START:Int = 0xDC00;
    private static final LOW_SURROGATE_END:Int = 0xDFFF;
    private static final CR:Int = 0x000D;
    private static final LF:Int = 0x000A;
    private static final ZWNJ:Int = 0x200C;
    private static final ZWJ:Int = 0x200D;

    public static function coerceToInteractionBoundary(text:String, offset:Int, range:TextRange, bias:SourceBoundaryBias):Int {
        final start:Int = clamp(range.start, 0, text.length);
        final end:Int = clamp(range.end, start, text.length);
        final target:Int = clamp(offset, start, end);
        if (target == start || target == end) {
            return target;
        }
        final boundaries:Array<Int> = interactionBoundariesByOffsets(text, start, end);
        var previous:Int = start;
        var next:Int = end;
        var index:Int = 0;
        while (index < boundaries.length) {
            final boundary:Int = boundaries[index];
            if (boundary == target) {
                return target;
            }
            if (boundary < target) {
                previous = boundary;
            } else {
                next = boundary;
                break;
            }
            index += 1;
        }
        if (bias == Backward) {
            return previous;
        }
        if (bias == Forward) {
            return next;
        }
        return target - previous < next - target ? previous : next;
    }

    public static function interactionBoundaries(text:String, range:TextRange):Array<Int> {
        final start:Int = clamp(range.start, 0, text.length);
        final end:Int = clamp(range.end, start, text.length);
        return interactionBoundariesByOffsets(text, start, end);
    }

    public static function sourceGraphemeBoundaries(text:String, range:TextRange):Array<Int> {
        return interactionBoundaries(text, range);
    }

    public static function codePointAtCompat(text:String, index:Int, end:Int):Int {
        final high:Int = text.charCodeAt(index);
        if (high < HIGH_SURROGATE_START || high > HIGH_SURROGATE_END || index + 1 >= end) {
            return high;
        }
        final low:Int = text.charCodeAt(index + 1);
        if (low < LOW_SURROGATE_START || low > LOW_SURROGATE_END) {
            return high;
        }
        return 0x10000 + ((high - HIGH_SURROGATE_START) << 10) + (low - LOW_SURROGATE_START);
    }

    private static function interactionBoundariesByOffsets(text:String, start:Int, end:Int):Array<Int> {
        final output:Array<Int> = [start];
        var index:Int = start;
        while (index < end) {
            final first:Int = codePointAtCompat(text, index, end);
            var next:Int = index + charCount(first);
            var precedingEmojiModifierBase:Bool = UnicodeEmojiModifierBaseData.contains(first);
            var precedingExtendedPictographic:Bool = UnicodeExtendedPictographicData.contains(first);

            if (first == CR && next < end && codePointAtCompat(text, next, end) == LF) {
                next += 1;
            } else if (isRegionalIndicator(first) && next < end) {
                final following:Int = codePointAtCompat(text, next, end);
                if (isRegionalIndicator(following)) {
                    next += charCount(following);
                }
            } else if (isHangulL(first)) {
                while (next < end && isHangulL(codePointAtCompat(text, next, end))) {
                    next += charCount(codePointAtCompat(text, next, end));
                }
                if (next < end && isHangulV(codePointAtCompat(text, next, end))) {
                    while (next < end && isHangulV(codePointAtCompat(text, next, end))) {
                        next += charCount(codePointAtCompat(text, next, end));
                    }
                    while (next < end && isHangulT(codePointAtCompat(text, next, end))) {
                        next += charCount(codePointAtCompat(text, next, end));
                    }
                }
            } else if (isHangulLvOrLvt(first)) {
                if (isHangulLv(first)) {
                    while (next < end && isHangulV(codePointAtCompat(text, next, end))) {
                        next += charCount(codePointAtCompat(text, next, end));
                    }
                }
                while (next < end && isHangulT(codePointAtCompat(text, next, end))) {
                    next += charCount(codePointAtCompat(text, next, end));
                }
            }

            next = consumeExtenders(text, next, end);
            if (precedingEmojiModifierBase && next < end && isEmojiModifier(codePointAtCompat(text, next, end))) {
                next += charCount(codePointAtCompat(text, next, end));
                precedingEmojiModifierBase = false;
                next = consumeExtenders(text, next, end);
            }
            while (next < end && codePointAtCompat(text, next, end) == ZWJ) {
                next += 1;
                if (next >= end) {
                    break;
                }
                final joined:Int = codePointAtCompat(text, next, end);
                if (!precedingExtendedPictographic || !UnicodeExtendedPictographicData.contains(joined)) {
                    break;
                }
                next += charCount(joined);
                precedingEmojiModifierBase = UnicodeEmojiModifierBaseData.contains(joined);
                precedingExtendedPictographic = true;
                next = consumeExtenders(text, next, end);
                if (precedingEmojiModifierBase && next < end && isEmojiModifier(codePointAtCompat(text, next, end))) {
                    next += charCount(codePointAtCompat(text, next, end));
                    precedingEmojiModifierBase = false;
                    next = consumeExtenders(text, next, end);
                }
            }
            index = next;
            output.push(index);
        }
        return output;
    }

    private static function consumeExtenders(text:String, from:Int, end:Int):Int {
        var index:Int = from;
        while (index < end) {
            final codePoint:Int = codePointAtCompat(text, index, end);
            if (!isInteractionExtender(codePoint)) {
                break;
            }
            index += charCount(codePoint);
        }
        return index;
    }

    private static function isInteractionExtender(codePoint:Int):Bool {
        return codePoint == ZWNJ
            || (codePoint >= 0xFE00 && codePoint <= 0xFE0F)
            || (codePoint >= 0xE0100 && codePoint <= 0xE01EF)
            || (codePoint >= 0xE0020 && codePoint <= 0xE007F)
            || isCombiningMark(codePoint);
    }

    private static function isCombiningMark(codePoint:Int):Bool {
        // Mirrors the Kotlin `this <= 0xFFFF && toChar().category in EXTENDING_CATEGORIES`
        // check over the generated Mn/Mc/Me range table (Unicode 17.0.0).
        return codePoint <= 0xFFFF && UnicodeCombiningMarkData.contains(codePoint);
    }

    private static function isEmojiModifier(codePoint:Int):Bool {
        return codePoint >= 0x1F3FB && codePoint <= 0x1F3FF;
    }

    private static function isRegionalIndicator(codePoint:Int):Bool {
        return codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF;
    }

    private static function isHangulL(codePoint:Int):Bool {
        return (codePoint >= 0x1100 && codePoint <= 0x115F) || (codePoint >= 0xA960 && codePoint <= 0xA97C);
    }

    private static function isHangulV(codePoint:Int):Bool {
        return (codePoint >= 0x1160 && codePoint <= 0x11A7) || (codePoint >= 0xD7B0 && codePoint <= 0xD7C6);
    }

    private static function isHangulT(codePoint:Int):Bool {
        return (codePoint >= 0x11A8 && codePoint <= 0x11FF) || (codePoint >= 0xD7CB && codePoint <= 0xD7FB);
    }

    private static function isHangulLvOrLvt(codePoint:Int):Bool {
        return codePoint >= 0xAC00 && codePoint <= 0xD7A3;
    }

    private static function isHangulLv(codePoint:Int):Bool {
        return isHangulLvOrLvt(codePoint) && (codePoint - 0xAC00) % 28 == 0;
    }

    private static function charCount(codePoint:Int):Int {
        return codePoint > 0xFFFF ? 2 : 1;
    }

    private static function clamp(value:Int, low:Int, high:Int):Int {
        if (value < low) {
            return low;
        }
        if (value > high) {
            return high;
        }
        return value;
    }
}
