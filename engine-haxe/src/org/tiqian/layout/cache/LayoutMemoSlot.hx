package org.tiqian.layout.cache;

/**
 * `LayoutMemoSlot`: one memoized value. `value` is null until the owner of the slot writes the
 * value it computed. A caller reads the slot, computes on a miss and writes the result back:
 *
 *     final cached = slot.value;
 *     final value = cached != null ? cached : compute();
 *     if (cached == null)
 *         slot.value = value;
 *
 * The slot has no method that takes the value. boring's Rust backend declares a method parameter
 * of the class type parameter as `&T`, while a call site borrows only Array, String, Bytes and
 * StringBuf arguments (`isPassByRef` in the Rust backend's `RustExpr`), so a `store(value:T)`
 * call does not compile for any other value type. The slot takes no compute function either:
 * boring's Swift backend emits a function-typed parameter as throwing only for zero-argument
 * `Void` functions (`SwiftType.isThrowingThunk`), and the computations stored here throw
 * `TiqianIllegalArgumentException`.
 *
 * The slot knows nothing about what it stores or when the stored value is valid: the owner of the
 * slot decides that by choosing which slot instance a computation reads. A slot is not
 * synchronized; it serves the thread that owns the engine holding it.
 */
class LayoutMemoSlot<T> {
    public var value:Null<T>;

    public function new() {
        this.value = null;
    }
}

/**
 * `IntKeyedLayoutMemoSlot`: one memoized value together with the integer key it was computed for.
 * `cached` returns `value` when the requested key equals `key`, and null otherwise. The owner
 * writes `key` and `value` together after computing a value, so the slot holds one key at a time.
 */
class IntKeyedLayoutMemoSlot<T> {
    public var key:Int;
    public var value:Null<T>;

    public function new() {
        this.key = 0;
        this.value = null;
    }

    public function cached(requestedKey:Int):Null<T> {
        return key == requestedKey ? value : null;
    }
}
