package org.tiqian.layout.cache;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class LayoutMemoSlotTest {
    @:test public static function slotIsEmptyUntilTheFirstWrite():Void {
        final t = new TestTraceRecorder("LayoutMemoSlotTest");
        t.section("slotIsEmptyUntilTheFirstWrite");
        final slot = LayoutMemoSlotTestSupport.newIntArraySlot();
        TracedAssertions.assertTrue(slot.value == null);
        final stored:Array<Int> = [7];
        slot.value = stored;
        final cached = slot.value;
        TracedAssertions.assertTrue(cached != null);
        TracedAssertions.assertEquals(7, cached[0]);
    }

    @:test public static function slotReplacesTheValueOnAnotherWrite():Void {
        final t = new TestTraceRecorder("LayoutMemoSlotTest");
        t.section("slotReplacesTheValueOnAnotherWrite");
        final slot = LayoutMemoSlotTestSupport.newIntArraySlot();
        final first:Array<Int> = [1];
        final second:Array<Int> = [2];
        slot.value = first;
        slot.value = second;
        final cached = slot.value;
        TracedAssertions.assertTrue(cached != null);
        TracedAssertions.assertEquals(2, cached[0]);
    }

    @:test public static function keyedSlotReturnsTheValueOnlyForItsKey():Void {
        final t = new TestTraceRecorder("LayoutMemoSlotTest");
        t.section("keyedSlotReturnsTheValueOnlyForItsKey");
        final slot = LayoutMemoSlotTestSupport.newKeyedIntArraySlot();
        TracedAssertions.assertTrue(slot.cached(0) == null, "an empty slot has no value even for its initial key");
        final stored:Array<Int> = [10];
        slot.key = 1;
        slot.value = stored;
        final sameKey = slot.cached(1);
        TracedAssertions.assertTrue(sameKey != null);
        TracedAssertions.assertEquals(10, sameKey[0]);
        TracedAssertions.assertTrue(slot.cached(2) == null);
    }

    @:test public static function keyedSlotHoldsOneKeyAtATime():Void {
        final t = new TestTraceRecorder("LayoutMemoSlotTest");
        t.section("keyedSlotHoldsOneKeyAtATime");
        final slot = LayoutMemoSlotTestSupport.newKeyedIntArraySlot();
        final first:Array<Int> = [10];
        final second:Array<Int> = [20];
        slot.key = 1;
        slot.value = first;
        slot.key = 2;
        slot.value = second;
        TracedAssertions.assertTrue(slot.cached(1) == null, "writing another key replaces the earlier entry");
        final current = slot.cached(2);
        TracedAssertions.assertTrue(current != null);
        TracedAssertions.assertEquals(20, current[0]);
    }
}
