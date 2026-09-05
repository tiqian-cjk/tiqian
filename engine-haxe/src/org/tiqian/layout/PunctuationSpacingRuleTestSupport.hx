package org.tiqian.layout;

import org.tiqian.clreq.ClreqPunctuationPolicies;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.clreq.PunctuationGluePlacement;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRange;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressor;

class PunctuationSpacingRuleTestSupport {
    public static final em:Float = 16.0;
    public static final builder:PunctuationAtomBuilder = new PunctuationAtomBuilder(PunctuationGluePlacement.MainlandSimplified);
    public static final compressor:PunctuationSpacingCompressor = new PunctuationSpacingCompressor();

    public static function atom(char:String, index:Int):PunctuationAtom {
        final a = builder.build(char, new TextRange(index, index + 1), em);
        if (a == null)
            throw new TiqianIllegalArgumentException(Message("atom build returned null for " + char));
        final polClass = ClreqPunctuationPolicies.classify(char);
        if (polClass == PunctuationClass.Other)
            throw new TiqianIllegalArgumentException(Message("unexpected punctuation class for " + char));
        return a;
    }
}
