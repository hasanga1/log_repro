import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/time;

// Repro for DITSUB-950: errors logged with key-value context.
// Choreo's logging query returns the "message" as LogEntry and every other
// key (error, orderId, ...) as LogContext. The console UI / export are
// expected to show only the message.
service / on new http:Listener(9090) {

    // Logs an error with an error value and extra key-values.
    resource function get failure() returns string {
        error err = error("something broke", code = 42, detail = "db timeout");
        log:printError("Failed to do X.", 'error = err, orderId = "123");
        return "logged error with context";
    }

    // Control: message only, no context.
    resource function get plain() returns string {
        log:printError("Plain error without context.");
        return "logged plain error";
    }

    // Info-level with context, to check non-error levels.
    resource function get info() returns string {
        log:printInfo("Order processed.", orderId = "123", status = "ok");
        return "logged info with context";
    }

    // Emits a JSON log line exactly like Ballerina's json log format, with a flat key only.
    resource function get jsonflat() returns string {
        io:println("{\"time\":\"" + time:utcToString(time:utcNow()) + "\", \"level\":\"ERROR\", " +
            "\"module\":\"creagent/log_repro\", \"message\":\"Failed JSON flat.\", \"orderId\":\"123\"}");
        return "logged json flat";
    }

    // Emits a JSON log line with a nested error object under "error".
    resource function get jsonnested() returns string {
        io:println("{\"time\":\"" + time:utcToString(time:utcNow()) + "\", \"level\":\"ERROR\", " +
            "\"module\":\"creagent/log_repro\", \"message\":\"Failed JSON nested.\", " +
            "\"error\":{\"causes\":[], \"message\":\"something broke\", \"detail\":{\"code\":42}}, " +
            "\"orderId\":\"123\"}");
        return "logged json nested";
    }
}
