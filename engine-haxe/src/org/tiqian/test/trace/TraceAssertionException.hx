package org.tiqian.test.trace;

class TraceAssertionException extends haxe.Exception {
    public final error:TraceAssertionError;

    public function new(error:TraceAssertionError) {
        this.error = error;
        super(TraceAssertionException.describe(error));
    }

    public static function describe(value:TraceAssertionError):String {
        return switch (value) {
            case AssertionFailed(message):
                message;
        };
    }
}
