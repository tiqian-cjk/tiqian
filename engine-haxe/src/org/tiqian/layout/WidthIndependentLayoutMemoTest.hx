package org.tiqian.layout;

import org.tiqian.clreq.KinsokuLevel;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationCacheFns;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class WidthIndependentLayoutMemoTest {
    @:test public static function memoKeepsOneSlotPerKinsokuLevel():Void {
        new TestTraceRecorder("WidthIndependentLayoutMemoTest").section("memoKeepsOneSlotPerKinsokuLevel");
        final memo = new WidthIndependentLayoutMemo();
        final count = WidthIndependentAnnotationCacheFns.KINSOKU_LEVEL_MEMO_KEY_COUNT;
        TracedAssertions.assertEquals(count, memo.kinsokuDependent.length);
        TracedAssertions.assertEquals(count, memo.planningKinsokuPart.length);
        TracedAssertions.assertEquals(count, memo.finishClusterLookups.length);
        final keys = [
            WidthIndependentAnnotationCacheFns.kinsokuLevelMemoKey(KinsokuLevel.None),
            WidthIndependentAnnotationCacheFns.kinsokuLevelMemoKey(KinsokuLevel.Basic),
            WidthIndependentAnnotationCacheFns.kinsokuLevelMemoKey(KinsokuLevel.GbStyle),
            WidthIndependentAnnotationCacheFns.kinsokuLevelMemoKey(KinsokuLevel.Strict)
        ];
        for (i in 0...keys.length) {
            TracedAssertions.assertTrue(keys[i] >= 0 && keys[i] < count);
            for (j in 0...i)
                TracedAssertions.assertTrue(keys[i] != keys[j]);
        }
    }
}
