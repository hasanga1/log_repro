import ballerina/http;
import ballerina/io;
import ballerina/time;

// Repro for DITSUB-950: Runtime Logs show logContext as {} for an HTTP-error log entry.
// /apierror reproduces the customer's shape; /ctx* endpoints isolate which part triggers it.
service / on new http:Listener(9090) {

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

    // ---- Bisect endpoints: each logs one JSON line whose context isolates one candidate trigger ----

    // A: only a header value containing quotes
    resource function get ctxquotes() returns string {
        emit("Bisect A quotes", {'error: {message: "x", detail: {headers: {"server-timing": ["t;desc=\"abc\", sem_wait;dur=0"]}}}});
        return "A";
    }

    // B: headers and cookies with ; = / characters, but no quotes
    resource function get ctxheaders() returns string {
        emit("Bisect B headers", {'error: {message: "x", detail: {headers: {
            "set-cookie": ["JSESSIONID=xxxx; Path=/; HttpOnly; Secure", "glide_user=; Max-Age=0; Path=/; HttpOnly"],
            "content-type": ["application/json;charset=UTF-8"], "cache-control": ["no-cache,no-store,max-age=-1"]}}}});
        return "B";
    }

    // C: stackTrace as an array of objects
    resource function get ctxstack() returns string {
        emit("Bisect C stack", {'error: {message: "x", stackTrace: [
            {callableName: "a", moduleName: "m", fileName: "f.bal", lineNumber: 1},
            {callableName: "b", moduleName: "m", fileName: "f.bal", lineNumber: 2}]}});
        return "C";
    }

    // D: large flat context (about 6 KB), nothing special in it
    resource function get ctxlarge() returns string {
        string filler = "";
        foreach int i in 1...300 {
            filler += "part" + i.toString() + "-xxxxxxxxxxxxxxxx ";
        }
        emit("Bisect D large", {detail: filler});
        return "D";
    }

    // E: nested body object with a message and detail, no headers
    resource function get ctxbody() returns string {
        emit("Bisect E body", {'error: {message: "Bad Request", detail: {statusCode: 400,
            body: {'error: {message: "Authentication failed", detail: "Invalid deployment ID"}, status: "failure"}}}});
        return "E";
    }
}

isolated function emit(string message, map<json> context) {
    map<json> line = {time: time:utcToString(time:utcNow()), level: "ERROR", module: "creagent/log_repro", message: message};
    foreach var [k, v] in context.entries() {
        line[k] = v;
    }
    io:println(line.toJsonString());
}
