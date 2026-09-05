package org.tiqian.clreq;

/**
 * How the kinsoku level and hanging style are chosen. Kotlin models this as
 * a sealed interface with two data classes; the port carries it as an enum
 * with payloads, and KinsokuModes owns the member logic the interface held.
 * Haxe enum constructors take no defaults, so the Kotlin defaults
 * (Fixed hanging Disabled; MeasureAdaptive 14/24/32 em) are written at every
 * construction site.
 */
enum KinsokuMode {
    Fixed(level:KinsokuLevel, hanging:HangingPunctuationStyle);
    MeasureAdaptive(hangBelowEm:Float, gbAboveEm:Float, strictAboveEm:Float);
}
