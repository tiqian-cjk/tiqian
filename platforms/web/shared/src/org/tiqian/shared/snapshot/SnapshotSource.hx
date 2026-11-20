package org.tiqian.shared.snapshot;

typedef FoldResult = {
    final text:String;
    final boundaryMap:Array<Int>;
};

class FoldState {
    public var projected:Array<String>;
    public var boundaryMap:Array<Int>;
    public var pendingStart:Int;
    public var pendingEnd:Int;

    public function new(length:Int) {
        this.projected = [];
        this.boundaryMap = [];
        var i = 0;
        while (i <= length) {
            this.boundaryMap.push(0);
            i++;
        }
        this.pendingStart = -1;
        this.pendingEnd = -1;
    }

    public function resolvePending(emit:Bool):Void {
        if (this.pendingStart < 0) {
            return;
        }
        var before = this.projected.length;
        if (emit && this.projected.length > 0 && this.projected[this.projected.length - 1] != "\n") {
            this.projected.push(" ");
        }
        var after = this.projected.length;
        this.boundaryMap[this.pendingStart] = before;
        var boundary = this.pendingStart + 1;
        while (boundary <= this.pendingEnd) {
            this.boundaryMap[boundary] = after;
            boundary++;
        }
        this.pendingStart = -1;
        this.pendingEnd = -1;
    }
}

class SnapshotSource {
    public static function isSafeTag(tagName:String):Bool {
        return tagName == "a" || tagName == "abbr" || tagName == "b" ||
            tagName == "bdi" || tagName == "bdo" || tagName == "cite" ||
            tagName == "code" || tagName == "data" || tagName == "del" ||
            tagName == "dfn" || tagName == "em" || tagName == "i" ||
            tagName == "ins" || tagName == "kbd" || tagName == "mark" ||
            tagName == "q" || tagName == "s" || tagName == "samp" ||
            tagName == "small" || tagName == "span" || tagName == "strong" ||
            tagName == "sub" || tagName == "sup" || tagName == "time" ||
            tagName == "u" || tagName == "var";
    }

    public static function isSupportedAttributeName(name:String):Bool {
        if (name == "style") {
            return false;
        }
        if (name.length >= 2 && name.substring(0, 2) == "on") {
            return false;
        }
        if (name.length >= 8 && name.substring(0, 8) == "data-tq-") {
            return false;
        }
        return matchesAttributeName(name);
    }

    public static function isUnsafeHref(value:String):Bool {
        var i = 0;
        while (i < value.length && isJsWhitespace(value.charCodeAt(i))) {
            i++;
        }
        if (i + 11 > value.length) {
            return false;
        }
        if (!isJavascriptWord(value.substring(i, i + 10))) {
            return false;
        }
        return value.charCodeAt(i + 10) == 58;
    }

    public static function foldNormalFlow(text:String, hardBreakOffsets:Array<Int>):FoldResult {
        var state = new FoldState(text.length);
        var hb = 0;
        var index = 0;
        while (index < text.length) {
            while (hb < hardBreakOffsets.length && hardBreakOffsets[hb] < index) {
                hb++;
            }
            var isHardBreak = text.charCodeAt(index) == 10 &&
                hb < hardBreakOffsets.length && hardBreakOffsets[hb] == index;
            if (isHardBreak) {
                state.resolvePending(false);
                state.boundaryMap[index] = state.projected.length;
                state.projected.push("\n");
                state.boundaryMap[index + 1] = state.projected.length;
                hb++;
            } else if (isCollapsibleWhitespace(text.charCodeAt(index))) {
                if (state.pendingStart < 0) {
                    state.pendingStart = index;
                    state.boundaryMap[index] = state.projected.length;
                }
                state.pendingEnd = index + 1;
            } else {
                state.resolvePending(true);
                state.boundaryMap[index] = state.projected.length;
                state.projected.push(text.substring(index, index + 1));
                state.boundaryMap[index + 1] = state.projected.length;
            }
            index++;
        }
        state.resolvePending(false);
        state.boundaryMap[text.length] = state.projected.length;
        return { text: state.projected.join(""), boundaryMap: state.boundaryMap };
    }

    private static function matchesAttributeName(name:String):Bool {
        if (name.length == 0) {
            return false;
        }
        if (!isAttributeStart(name.charCodeAt(0))) {
            return false;
        }
        var i = 1;
        while (i < name.length) {
            if (!isAttributePart(name.charCodeAt(i))) {
                return false;
            }
            i++;
        }
        return true;
    }

    private static function isAttributeStart(code:Int):Bool {
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
            code == 95 || code == 58;
    }

    private static function isAttributePart(code:Int):Bool {
        return isAttributeStart(code) || (code >= 48 && code <= 57) ||
            code == 46 || code == 45;
    }

    private static function isJavascriptWord(word:String):Bool {
        return (word.charCodeAt(0) == 106 || word.charCodeAt(0) == 74) &&
            (word.charCodeAt(1) == 97 || word.charCodeAt(1) == 65) &&
            (word.charCodeAt(2) == 118 || word.charCodeAt(2) == 86) &&
            (word.charCodeAt(3) == 97 || word.charCodeAt(3) == 65) &&
            (word.charCodeAt(4) == 115 || word.charCodeAt(4) == 83) &&
            (word.charCodeAt(5) == 99 || word.charCodeAt(5) == 67) &&
            (word.charCodeAt(6) == 114 || word.charCodeAt(6) == 82) &&
            (word.charCodeAt(7) == 105 || word.charCodeAt(7) == 73) &&
            (word.charCodeAt(8) == 112 || word.charCodeAt(8) == 80) &&
            (word.charCodeAt(9) == 116 || word.charCodeAt(9) == 84);
    }

    private static function isJsWhitespace(code:Int):Bool {
        return code == 9 || code == 10 || code == 11 || code == 12 || code == 13 ||
            code == 32 || code == 160 || code == 5760 ||
            (code >= 8192 && code <= 8202) || code == 8232 || code == 8233 ||
            code == 8239 || code == 8287 || code == 12288 || code == 65279;
    }

    private static function isCollapsibleWhitespace(code:Int):Bool {
        return code == 32 || code == 9 || code == 10 || code == 13 || code == 12;
    }
}

