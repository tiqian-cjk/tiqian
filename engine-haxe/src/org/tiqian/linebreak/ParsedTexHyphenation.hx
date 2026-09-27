package org.tiqian.linebreak;

class ParsedTexHyphenation {
    public final patterns:runtime.SortedTable.SortedMapTable<String, Array<Int>>;
    public final exceptions:runtime.SortedTable.SortedMapTable<String, Array<Int>>;

    public function new(patterns:runtime.SortedTable.SortedMapTable<String, Array<Int>>, exceptions:runtime.SortedTable.SortedMapTable<String, Array<Int>>) {
        this.patterns = patterns;
        this.exceptions = exceptions;
    }
}
