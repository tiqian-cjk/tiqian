package org.tiqian.layout;

import org.tiqian.clreq.CjkPunctuationGlyphSubstitution;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.font.FontRole;

class ContextualPunctuationDisplaySubstitutionFns {
    public static function substituteForRole(self:ClreqPunctuationGlyphSubstitutor, sourceText:String, role:FontRole):CjkPunctuationGlyphSubstitution {
        final candidate = self.substitute(sourceText);
        return role == FontRole.CjkPunctuation
            || candidate.displayText == sourceText ? candidate : new CjkPunctuationGlyphSubstitution(sourceText, sourceText,
                "CjkRoleGatedDisplaySubstitution:preserve-role-" + role);
    }
}
