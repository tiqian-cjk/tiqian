package org.tiqian.clreq;

import org.tiqian.core.BuiltInLayoutProfiles;
import org.tiqian.core.LayoutProfileId;

interface ClreqProfileResolver {
    function resolve(profileId:LayoutProfileId):ClreqProfile;
}

class BuiltInClreqProfileResolver implements ClreqProfileResolver {
    public function new() {}

    public function resolve(profileId:LayoutProfileId):ClreqProfile {
        if (profileId.value == BuiltInLayoutProfiles.ClreqHorizontal.value || profileId.value == ClreqProfile.MainlandHorizontal.id) {
            return ClreqProfile.MainlandHorizontal;
        }
        return ClreqProfile.MainlandHorizontal;
    }
}
