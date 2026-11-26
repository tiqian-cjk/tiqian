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
}
