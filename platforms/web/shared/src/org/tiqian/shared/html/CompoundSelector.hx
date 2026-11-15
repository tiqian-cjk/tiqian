package org.tiqian.shared.html;

/**
 * One compound selector of an element.closest(...) list, ported from
 * platforms/web/server/precompute/engine/src/html_parse.rs L450-500. The
 * accepted forms cover the package defaults and prose hosts: a type
 * selector, '*', '#id', '.class', '[attr]', and '[attr=value]' with a bare
 * or quoted value. Anything else reports UnsupportedHtmlAncestorSelector
 * instead of guessing.
 */
class CompoundSelector {
    public final tag:Null<String>;
    public final id:Null<String>;
    public final classes:Array<String>;
    public final attributes:Array<CompoundAttribute>;

    public function new(tag:Null<String>, id:Null<String>, classes:Array<String>,
            attributes:Array<CompoundAttribute>) {
        this.tag = tag;
        this.id = id;
        this.classes = classes;
        this.attributes = attributes;
    }

    /**
     * Whether the element matches this compound. The tag, id and attribute
     * names compare the way the Rust lane compares them (ASCII case
     * insensitive names, exact values).
     */
    public function matches(parser:DomParser, element:DomNode):Bool {
        if (this.tag != null && this.tag != parser.tagName(element)) {
            return false;
        }
        if (this.id != null) {
            final actualId = parser.attributeValue(element, "id");
            if (actualId == null || actualId != this.id) {
                return false;
            }
        }
        if (this.classes.length > 0) {
            final classAttribute = parser.attributeValue(element, "class");
            final present = splitAsciiWhitespace(classAttribute == null ? "" : classAttribute);
            for (className in this.classes) {
                if (present.indexOf(className) < 0) {
                    return false;
                }
            }
        }
        for (attribute in this.attributes) {
            final actual = parser.attributeValue(element, attribute.name);
            if (attribute.value == null) {
                if (actual == null) {
                    return false;
                }
            } else if (actual != attribute.value) {
                return false;
            }
        }
        return true;
    }

    /** Parses a comma separated selector list for closest. */
    public static function parseCompoundSelectorList(selector:String):Array<CompoundSelector> {
        final compounds:Array<CompoundSelector> = [];
        for (part in selector.split(",")) {
            final trimmed = jsSelectorTrim(part);
            if (trimmed.length == 0) {
                throw unsupported();
            }
            compounds.push(parseCompoundSelector(trimmed));
        }
        return compounds;
    }

    static function parseCompoundSelector(input:String):CompoundSelector {
        var tag:Null<String> = null;
        var id:Null<String> = null;
        final classes:Array<String> = [];
        final attributes:Array<CompoundAttribute> = [];
        var position = 0;
        while (position < input.length) {
            final code:Int = input.charCodeAt(position);
            if (code == 0x2A && position == 0 && tag == null) {
                // '*' alone matches every element; it selects nothing itself.
                position += 1;
            } else if (code == 0x2E) {
                position += 1;
                final word = readSelectorWord(input, position, false);
                classes.push(word.name);
                position = word.next;
            } else if (code == 0x23) {
                position += 1;
                if (id != null) {
                    throw unsupported();
                }
                final word = readSelectorWord(input, position, false);
                id = word.name;
                position = word.next;
            } else if (code == 0x5B) {
                position += 1;
                final nameWord = readSelectorWord(input, position, true);
                final name = nameWord.name;
                position = nameWord.next;
                if (position >= input.length) {
                    throw unsupported();
                }
                if (input.charCodeAt(position) == 0x5D) {
                    position += 1;
                    attributes.push({ name: name, value: null });
                    continue;
                }
                if (input.charCodeAt(position) != 0x3D) {
                    throw unsupported();
                }
                position += 1;
                final value = new StringBuf();
                if (position < input.length
                    && (input.charCodeAt(position) == 0x22 || input.charCodeAt(position) == 0x27)) {
                    final quote:Int = input.charCodeAt(position);
                    position += 1;
                    while (true) {
                        if (position >= input.length) {
                            throw unsupported();
                        }
                        final unit:Int = input.charCodeAt(position);
                        if (unit == quote) {
                            position += 1;
                            break;
                        }
                        value.add(input.charAt(position));
                        position += 1;
                    }
                } else {
                    while (true) {
                        if (position >= input.length) {
                            throw unsupported();
                        }
                        final unit:Int = input.charCodeAt(position);
                        if (unit == 0x5D) {
                            break;
                        }
                        if (!isSelectorWordCharacter(unit, false)) {
                            throw unsupported();
                        }
                        value.add(input.charAt(position));
                        position += 1;
                    }
                }
                if (position >= input.length || input.charCodeAt(position) != 0x5D) {
                    throw unsupported();
                }
                position += 1;
                attributes.push({ name: name, value: value.toString() });
            } else if (isSelectorWordStart(code)) {
                if (tag != null || position != 0) {
                    throw unsupported();
                }
                final word = readSelectorWord(input, position, false);
                tag = HtmlNameCase.asciiLower(word.name);
                position = word.next;
            } else {
                throw unsupported();
            }
        }
        return new CompoundSelector(tag, id, classes, attributes);
    }

    /** Reads one identifier; a bare attribute value accepts the wider word set. */
    static function readSelectorWord(input:String, position:Int, attributeName:Bool):SelectorWord {
        if (position >= input.length || !isSelectorWordStart(input.charCodeAt(position))) {
            throw unsupported();
        }
        var index = position;
        while (index < input.length && isSelectorWordCharacter(input.charCodeAt(index), attributeName)) {
            index += 1;
        }
        return { name: input.substring(position, index), next: index };
    }

    static function isSelectorWordStart(code:Int):Bool {
        return (code >= 0x41 && code <= 0x5A)
            || (code >= 0x61 && code <= 0x7A)
            || code == 0x5F
            || code == 0x2D;
    }

    static function isSelectorWordCharacter(code:Int, attributeName:Bool):Bool {
        if (isSelectorWordStart(code) || (code >= 0x30 && code <= 0x39)) {
            return true;
        }
        return attributeName && code == 0x3A;
    }

    /** JS whitespace trimming used by the Rust lane's js_selector_trim. */
    static function jsSelectorTrim(value:String):String {
        var start = 0;
        var end = value.length - 1;
        while (start <= end && isSelectorTrimWhitespace(value.charCodeAt(start))) {
            start += 1;
        }
        while (end >= start && isSelectorTrimWhitespace(value.charCodeAt(end))) {
            end -= 1;
        }
        return value.substring(start, end + 1);
    }

    static function isSelectorTrimWhitespace(code:Int):Bool {
        return code == 0x09 || code == 0x0A || code == 0x0C || code == 0x0D || code == 0x20;
    }

    /** The class attribute splits on ASCII whitespace, like split_ascii_whitespace. */
    static function splitAsciiWhitespace(value:String):Array<String> {
        final result:Array<String> = [];
        var start = 0;
        var index = 0;
        while (index < value.length) {
            final code:Int = value.charCodeAt(index);
            if (code == 0x09 || code == 0x0A || code == 0x0C || code == 0x0D || code == 0x20) {
                if (start < index) {
                    result.push(value.substring(start, index));
                }
                start = index + 1;
            }
            index += 1;
        }
        if (start < value.length) {
            result.push(value.substring(start, value.length));
        }
        return result;
    }

    static function unsupported():HtmlParseException {
        return new HtmlParseException(HtmlError.UnsupportedHtmlAncestorSelector);
    }
}

typedef CompoundAttribute = {
    final name:String;
    final value:Null<String>;
}

typedef SelectorWord = {
    final name:String;
    final next:Int;
}
