package org.tiqian.linebreak;

interface Hyphenator {
    public function hyphenate(word:String):std.ReadOnlyArray<Int>;
}

class NoHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(word:String):std.ReadOnlyArray<Int>
        return [];
}

class TailHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(word:String):std.ReadOnlyArray<Int> {
        return [word.length - 5];
    }
}

class SyllableHyphenator implements Hyphenator {
    final points:Array<Int>;

    public function new(points:Array<Int>) {
        this.points = points;
    }

    public function hyphenate(word:String):std.ReadOnlyArray<Int> {
        return points;
    }
}
