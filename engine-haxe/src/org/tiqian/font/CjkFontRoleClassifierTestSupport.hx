package org.tiqian.font;

import org.tiqian.core.TextRange;

class CjkFontRoleClassifierTestSupport {
    public static function c(t:String, s:Int, e:Int):FontRole
        return new CjkFontRoleClassifier().classify(t, new TextRange(s, e));
}
