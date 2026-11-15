package org.tiqian.shared;

/**
 * The value-style declaration internment registry: a declaration maps to the
 * first position at which it appeared (declarations.length before the push),
 * which is the rule the Rust precompute (intern_value_style in
 * snapshot_tables.rs) and the hand-written TypeScript lane
 * (registerPreparedValueStyle in prepared-dom.ts) both applied. Linear scan
 * keeps the single source free of any hash-map ordering; the index returned
 * feeds snapshotValueStyleClass so the snapshot class stays stable.
 */
class ValueStyleInterner {
    public final declarations:Array<String>;

    public function new() {
        declarations = [];
    }

    public function intern(declaration:String):Int {
        for (i in 0...declarations.length) {
            if (declarations[i] == declaration) {
                return i;
            }
        }
        final index = declarations.length;
        declarations.push(declaration);
        return index;
    }

    public function at(index:Int):String {
        return declarations[index];
    }

    public function size():Int {
        return declarations.length;
    }
}

// Append-only invariant: intern never reorders or removes, so the index it
// returns stays a stable base-36 identifier feeding snapshotValueStyleClass.
