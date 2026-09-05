package org.tiqian.layout;

using std.Functional;

import org.tiqian.clreq.ClreqPunctuationPolicies;
import org.tiqian.clreq.KinsokuLevel;
import org.tiqian.core.Cluster;

/**
 * Line-start / line-end forbiddance for CJK punctuation. The default
 * ClreqKinsokuRule reads from ClreqPunctuationPolicies at the given level.
 */
interface KinsokuRule {
    function forbiddenAtLineStart(cluster:Cluster):Bool;
    function forbiddenAtLineEnd(cluster:Cluster):Bool;
}

class ClreqKinsokuRule implements KinsokuRule {
    private final level:KinsokuLevel;

    public function new(?level:Null<KinsokuLevel>) {
        this.level = level == null ? KinsokuLevel.Basic : level;
    }

    public function forbiddenAtLineStart(cluster:Cluster):Bool {
        if (cluster.displayText.length == 0) {
            return false;
        }
        return ClreqPunctuationPolicies.forbiddenAtLineStart(cluster.displayText.substring(0, 1), level);
    }

    public function forbiddenAtLineEnd(cluster:Cluster):Bool {
        if (cluster.displayText.length == 0) {
            return false;
        }
        return ClreqPunctuationPolicies.forbiddenAtLineEnd(cluster.displayText.substring(0, 1), level);
    }
}
