package org.tiqian.core;

// `LinkAddressDisplayGate`: whether a link's visible text is its own address — identical to
class LinkAddressDisplay {
    public static function displaysAddress(display:String, target:String):Bool {
        if (display.length == 0 || target.length == 0) {
            return false;
        }
        if (display == target) {
            return true;
        }
        return target == "https://" + display || target == "http://" + display || target == "mailto:" + display;
    }
}
