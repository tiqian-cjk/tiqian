package org.tiqian.shared.html;

/**
 * The shared HTML scan and injection lane, ported verbatim from the Rust
 * addon (platforms/web/server/precompute/engine/src/precompute_html.rs).
 *
 * findHtmlOpeningTags ports find_html_opening_tags L94-170: a UTF-16
 * code-unit scan that skips comments, quoted attributes, raw-text elements
 * and template contents, returning one record per selected opening tag.
 *
 * injectHtmlAttributes ports inject_html_attributes L219-258: a stable
 * descending sort by offset (NaN compares equal) followed by left-to-right
 * splice of each attribute into a growing string, gated on safe-integer
 * offsets within the current length.
 */
class HtmlScan {
    public static function findHtmlOpeningTags(html:String, tagNames:Array<String>):Array<HtmlOpeningTag> {
        final lower = html.toLowerCase();
        final selected:Array<String> = [];
        for (name in tagNames) {
            selected.push(name.toLowerCase());
        }
        final tags:Array<HtmlOpeningTag> = [];
        var templateDepth = 0;
        var cursor = html.indexOf("<");
        while (cursor >= 0) {
            final start = cursor;
            if (html.substr(start, 4) == "<!--") {
                final commentEnd = html.indexOf("-->", start + 4);
                if (commentEnd < 0) {
                    break;
                }
                cursor = html.indexOf("<", commentEnd + 3);
                continue;
            }
            var end = start + 1;
            var quote = -1;
            while (end < html.length) {
                final character:Int = html.charCodeAt(end);
                if (quote >= 0) {
                    if (character == quote) {
                        quote = -1;
                    }
                } else if (character == 0x22 || character == 0x27) {
                    quote = character;
                } else if (character == 0x3E) {
                    break;
                }
                end += 1;
            }
            if (end >= html.length) {
                break;
            }
            final source = html.substring(start, end + 1);
            final parsed = parseTagSource(source);
            if (parsed == null) {
                cursor = html.indexOf("<", end + 1);
                continue;
            }
            final closing = parsed.closing;
            final tagName = parsed.tagName;
            final selfClosing = StringTools.endsWith(source, "/>");
            if (!closing && tagName == "plaintext") {
                break;
            }
            if (!closing && isRawTextElement(tagName)) {
                final closingStart = lower.indexOf("</" + tagName, end + 1);
                if (closingStart < 0) {
                    break;
                }
                final closingEnd = html.indexOf(">", closingStart + tagName.length + 2);
                if (closingEnd < 0) {
                    break;
                }
                cursor = html.indexOf("<", closingEnd + 1);
                continue;
            }
            if (tagName == "template") {
                if (closing) {
                    templateDepth -= 1;
                    if (templateDepth < 0) {
                        templateDepth = 0;
                    }
                } else if (!selfClosing) {
                    templateDepth += 1;
                }
            } else if (!closing && selected.indexOf(tagName) >= 0 && templateDepth == 0) {
                tags.push({ end: end, source: source, tagName: tagName });
            }
            cursor = html.indexOf("<", end + 1);
        }
        return tags;
    }

    public static function injectHtmlAttributes(html:String, insertions:Array<HtmlAttributeInsertion>):String {
        final rows = insertions.copy();
        var i = 1;
        while (i < rows.length) {
            final key = rows[i];
            var j = i - 1;
            while (j >= 0 && rows[j].offset < key.offset) {
                rows[j + 1] = rows[j];
                j -= 1;
            }
            rows[j + 1] = key;
            i += 1;
        }
        var result = html;
        for (row in rows) {
            final offset = row.offset;
            final safeInteger = offset % 1.0 == 0.0 && Math.abs(offset) <= 9007199254740991.0;
            final length:Float = result.length;
            if (!safeInteger || offset < 0.0 || offset > length) {
                throw new HtmlParseException(HtmlError.InvalidHtmlAttributeInsertionOffset);
            }
            final at = Std.int(offset);
            result = result.substring(0, at) + row.attribute + result.substring(at);
        }
        return result;
    }

    private static function parseTagSource(source:String):Null<ParsedTag> {
        if (source.charAt(0) != "<") {
            return null;
        }
        var position = 1;
        final closing = source.charAt(position) == "/";
        if (closing) {
            position += 1;
        }
        if (position >= source.length) {
            return null;
        }
        final first:Int = source.charCodeAt(position);
        if (!isAsciiAlphabetic(first)) {
            return null;
        }
        position += 1;
        while (position < source.length) {
            final next:Int = source.charCodeAt(position);
            if (isAsciiAlphanumeric(next) || next == 0x2D) {
                position += 1;
            } else {
                break;
            }
        }
        final tagName = source.substring(closing ? 2 : 1, position).toLowerCase();
        if (position >= source.length) {
            return null;
        }
        final follow:Int = source.charCodeAt(position);
        if (isJsWhitespace(follow)) {
            return new ParsedTag(closing, tagName);
        }
        if (follow == 0x3E) {
            return new ParsedTag(closing, tagName);
        }
        if (follow == 0x2F) {
            if (position + 1 >= source.length) {
                return null;
            }
            final nextFollow:Int = source.charCodeAt(position + 1);
            if (nextFollow == 0x3E) {
                return new ParsedTag(closing, tagName);
            }
        }
        return null;
    }

    private static function isRawTextElement(tagName:String):Bool {
        return tagName == "iframe"
            || tagName == "noembed"
            || tagName == "noframes"
            || tagName == "noscript"
            || tagName == "script"
            || tagName == "style"
            || tagName == "textarea"
            || tagName == "title"
            || tagName == "xmp";
    }

    private static function isAsciiAlphabetic(code:Int):Bool {
        return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
    }

    private static function isAsciiAlphanumeric(code:Int):Bool {
        return isAsciiAlphabetic(code) || (code >= 0x30 && code <= 0x39);
    }

    private static function isJsWhitespace(code:Int):Bool {
        return code == 0x09 || code == 0x0A || code == 0x0B || code == 0x0C
            || code == 0x0D || code == 0x20 || code == 0xA0 || code == 0x1680
            || (code >= 0x2000 && code <= 0x200A)
            || code == 0x2028 || code == 0x2029 || code == 0x202F || code == 0x205F
            || code == 0x3000 || code == 0xFEFF;
    }
}

private class ParsedTag {
    public var closing:Bool;
    public var tagName:String;

    public function new(closing:Bool, tagName:String) {
        this.closing = closing;
        this.tagName = tagName;
    }
}
