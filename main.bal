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

    // JSON log whose message has embedded newlines (message + stack trace style), no extra keys.
    resource function get jsonmultiline() returns string {
        io:println("{\"time\":\"" + time:utcToString(time:utcNow()) + "\", \"level\":\"ERROR\", " +
            "\"message\":\"Failed multiline.\\nerror: something broke\\n\\tat main.bal:12\\n\\tat main.bal:30\"}");
        return "logged json multiline";
    }

    // JSON log with a very long message (about 6000 chars), no extra keys.
    resource function get jsonlong() returns string {
        string filler = "";
        foreach int i in 1...300 {
            filler += "part" + i.toString() + "-xxxxxxxxxxxxxxxx ";
        }
        io:println("{\"time\":\"" + time:utcToString(time:utcNow()) + "\", \"level\":\"ERROR\", " +
            "\"message\":\"Failed long. " + filler + "END\"}");
        return "logged json long";
    }

    // Mock upstream (like the customer's ServiceNow call): returns 400 with a header whose value contains quotes.
    resource function post backend/x() returns http:Response {
        http:Response r = new;
        r.statusCode = 400;
        r.setHeader("Server-Timing", "t;desc=\"abc\", sem_wait;dur=0, sesh_wait;dur=0");
        r.addHeader("Set-Cookie", "JSESSIONID=xxxx; Path=/; HttpOnly; Secure");
        r.addHeader("Set-Cookie", "glide_user=; Max-Age=0; Path=/; HttpOnly");
        r.setJsonPayload({'error: {message: "Authentication failed", detail: "Invalid deployment ID"}, status: "failure"});
        return r;
    }

    // Calls the mock upstream, then logs the failure as a JSON line with the full error (same shape as the customer's).
    resource function get apierror() returns string|error {
        http:Client c = check new ("http://localhost:9090/backend");
        json|error res = c->post("/x", {a: 1});
        if res is error {
            json[] frames = from var f in res.stackTrace()
                select {callableName: f.toString()};
            json detail = {};
            if res is http:ApplicationResponseError {
                var d = res.detail();
                detail = {statusCode: d.statusCode, headers: d.headers.toJson(), body: d.body.toJson()};
            }
            json line = {
                time: time:utcToString(time:utcNow()),
                level: "ERROR",
                module: "creagent/log_repro",
                message: "Failed to add usage statistics.",
                'error: {causes: [], message: res.message(), detail: detail, stackTrace: frames},
                nodeId: "aa13e131c3b3223aaeba988ec29f19a95ab422a76c73b2207c3abbfba525b688"
            };
            io:println(line.toJsonString());
        }
        return "logged api error";
    }
}
