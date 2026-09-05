package org.tiqian.core;

class TiqianIllegalArgumentException extends haxe.Exception {
    public final error:TextRangeError;

    public function new(error:TextRangeError) {
        this.error = error;
        super(TiqianIllegalArgumentException.describe(error));
    }

    public static function describe(error:TextRangeError):String {
        return switch (error) {
            case StartGreaterThanEnd:
                "TextRange start must not be greater than end.";
            case NegativeStart:
                "TextRange start must be non-negative.";
            case Message(text):
                text;
        };
    }
}
