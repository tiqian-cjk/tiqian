package org.tiqian.font;

import org.tiqian.font.FontMetrics.FontMetricsRequest;

class ScriptAwareFontMetricsNormalizerTestSupport {
    public static function req(key:String, role:FontRole):FontMetricsRequest
        return new FontMetricsRequest(key, 16, role, "zh-Hans");
}
