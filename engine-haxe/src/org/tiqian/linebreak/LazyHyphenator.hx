package org.tiqian.linebreak;

/** Builds a hyphenator when a `LazyHyphenator` first needs one. */
interface HyphenatorSource {
    public function createHyphenator():Hyphenator;
}

/**
 * A hyphenator slot that stays empty until the first `hyphenate` call
 * (`LazyHyphenatorSlot`). The first call asks `source` for the hyphenator and keeps it for every
 * later call, so a paragraph without a hyphenation candidate never loads hyphenation data. The
 * slot belongs to one engine instance: engines that lay out on different threads each hold
 * their own slot, and the slot needs no synchronization. A host plugs in another language by
 * passing a different `HyphenatorSource`, or passes any `Hyphenator` to the engine directly.
 */
class LazyHyphenator implements Hyphenator {
    final source:HyphenatorSource;
    var built:Null<Hyphenator>;

    public function new(source:HyphenatorSource) {
        this.source = source;
        this.built = null;
    }

    public function hyphenate(word:String):std.ReadOnlyArray<Int> {
        final existing = built;
        if (existing != null)
            return existing.hyphenate(word);
        final created:Hyphenator = source.createHyphenator();
        built = created;
        return created.hyphenate(word);
    }
}
