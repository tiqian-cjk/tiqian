package org.tiqian.core;

enum NoSuchElementError {
    Message(text:String);
}

/**
 * Missing-element exception for the first() sites that mirror the Kotlin
 * builtin NoSuchElementException. The Tiqian prefix keeps the throwing
 * origin recognizable in catch clauses.
 */
class TiqianNoSuchElementException extends haxe.Exception {
    public final error:NoSuchElementError;

    public function new(error:NoSuchElementError) {
        this.error = error;
        super(TiqianNoSuchElementException.describe(error));
    }

    public static function describe(error:NoSuchElementError):String {
        return switch (error) {
            case Message(text):
                text;
        }
    }
}
