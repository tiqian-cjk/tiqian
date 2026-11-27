package org.tiqian.layout;

import std.SortedSet;

/**
 * `EmptyClusterIndexSet` holds one empty set of cluster indices for `LineCandidate.NoHanging`.
 * boring accepts only null, literal, array and `new` forms as static field initializers, so the
 * static constant holds this class and its constructor builds the set. The class has its own
 * module: the TypeScript target then emits it as a module that `LineOptimization` imports, so it
 * is initialized before `LineCandidate.NoHanging` runs at module load.
 */
class EmptyClusterIndexSet {
    public final value:SortedSet<Int>;

    public function new() {
        final b = SortedSet.builder();
        this.value = b.build();
    }
}
