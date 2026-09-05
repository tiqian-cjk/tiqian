package org.tiqian.layout;

import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineOptimization.LineCandidate;
import std.SortedSet;

class LineCandidateValidationTestSupport {
    public static function candidate(hanging:Array<Int>, ?range:Null<IntRange>):LineCandidate {
        final b = SortedSet.builder();
        for (value in hanging)
            b.put(value);
        return new LineCandidate(range == null ? new IntRange(0, 3) : range, new TextRange(0, 4), 64.0, 64.0, null, null, null, b.build());
    }
}
