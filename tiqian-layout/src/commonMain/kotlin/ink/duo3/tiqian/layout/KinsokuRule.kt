package ink.duo3.tiqian.layout

import ink.duo3.tiqian.clreq.ClreqPunctuationPolicies
import ink.duo3.tiqian.core.Cluster

/**
 * KinsokuRule — line-start / line-end forbiddance for CJK punctuation.
 *
 * Default [ClreqKinsokuRule] reads from [ClreqPunctuationPolicies], which is
 * derived from the cluster's first display character. Profile-specific
 * overrides should subclass or replace this rule, not edit the engine.
 */
interface KinsokuRule {
    fun forbiddenAtLineStart(cluster: Cluster): Boolean
    fun forbiddenAtLineEnd(cluster: Cluster): Boolean
}

class ClreqKinsokuRule : KinsokuRule {
    override fun forbiddenAtLineStart(cluster: Cluster): Boolean {
        val char = cluster.displayText.firstOrNull() ?: return false
        return !ClreqPunctuationPolicies.policyFor(char).allowAtLineStart
    }

    override fun forbiddenAtLineEnd(cluster: Cluster): Boolean {
        val char = cluster.displayText.firstOrNull() ?: return false
        return !ClreqPunctuationPolicies.policyFor(char).allowAtLineEnd
    }
}
