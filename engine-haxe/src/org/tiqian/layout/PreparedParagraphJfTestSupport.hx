package org.tiqian.layout;

import org.tiqian.core.*;

class PreparedParagraphJfTestSupport {
    public static function line(range:TextRange, clusterRange:IntRange, ?naturalWidth:Null<Float>):LineBox {
        final width = naturalWidth == null ? 26.0 : naturalWidth;
        return new LineBox(range, clusterRange, 20, 0, 24, width, width, width, null, null, null, null, null, new LineDebugInfo(null));
    }
}
