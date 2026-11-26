package org.tiqian.layout.cache;

/**
 * `LayoutMemoSlotTestSupport`: creates the slots `LayoutMemoSlotTest` exercises. The slots are
 * created through functions with a declared return type because boring's Kotlin backend drops
 * both the type arguments of `new` and the declared type of a local, so `kotlinc` infers a slot's
 * type parameter only from a declared return or field type.
 */
class LayoutMemoSlotTestSupport {
    public static function newIntArraySlot():LayoutMemoSlot<Array<Int>> {
        return new LayoutMemoSlot<Array<Int>>();
    }
}
