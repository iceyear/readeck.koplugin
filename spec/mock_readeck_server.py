#!/usr/bin/env python3
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


STATE = {
    "annotations": [
        {
            "id": "remote-existing",
            "text": "remote text",
            "note": "remote note",
            "color": "yellow",
            "start_selector": "section/p[1]",
            "start_offset": 0,
            "end_selector": "section/p[1]",
            "end_offset": 11,
            "created": "2026-05-06T17:47:45Z",
        }
    ],
    "annotation_posts": [],
    "oauth_clients": [],
    "oauth_token_requests": 0,
}

CONFIG = {
    "version": "0.22.2",
    "features": ["oauth"],
}

ARTICLE_ID = "A1b2C3d4E5f6G7h8I9"


def parse_version(version):
    parts = []
    for part in str(version or "").split("."):
        digits = ""
        for char in part:
            if char.isdigit():
                digits += char
            else:
                break
        if digits == "":
            break
        parts.append(int(digits))
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def version_at_least(target):
    return parse_version(CONFIG["version"]) >= parse_version(target)


def annotation_notes_supported():
    return "annotation_notes" in CONFIG["features"] or version_at_least("0.22.2")


def annotation_none_color_supported():
    return "annotation_none_color" in CONFIG["features"] or version_at_least("0.22.2")


def write_json(handler, payload, status=200):
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def read_body(handler):
    length = int(handler.headers.get("Content-Length", "0") or "0")
    return handler.rfile.read(length) if length > 0 else b""


def request_payload(handler):
    body = read_body(handler)
    content_type = handler.headers.get("Content-Type", "")
    if "application/json" in content_type:
        return json.loads(body.decode("utf-8") or "{}")

    if "application/x-www-form-urlencoded" in content_type:
        form = parse_qs(body.decode("utf-8"), keep_blank_values=True)
        return {key: values[-1] if len(values) == 1 else values for key, values in form.items()}

    return {}


def list_value(value):
    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def form_error(field, message):
    return {"is_valid": False, "errors": {field: [message]}}


def validate_oauth_client(payload):
    required = ["client_name", "client_uri", "software_id", "software_version", "grant_types"]
    for field in required:
        value = payload.get(field)
        if value is None or value == "" or value == []:
            return form_error(field, "required")

    if len(str(payload["software_version"])) > 64:
        return form_error("software_version", "max length is 64")

    if "urn:ietf:params:oauth:grant-type:device_code" not in list_value(payload.get("grant_types")):
        return form_error("grant_types", "unsupported grant type")

    return None


def normalize_annotation(annotation):
    item = dict(annotation)
    if not annotation_notes_supported():
        item.pop("note", None)
    if item.get("color") == "none" and not annotation_none_color_supported():
        item["color"] = "yellow"
    return item


def validate_annotation(payload):
    required = ["start_selector", "start_offset", "end_selector", "end_offset", "color"]
    for field in required:
        value = payload.get(field)
        if value is None or value == "":
            return form_error(field, "required")

    for field in ["start_selector", "end_selector"]:
        if len(str(payload[field])) > 256:
            return form_error(field, "max length is 256")

    for field in ["start_offset", "end_offset"]:
        try:
            value = int(payload[field])
        except (TypeError, ValueError):
            return form_error(field, "must be an integer")
        if value < 0:
            return form_error(field, "must be greater than or equal to 0")

    color = str(payload["color"])
    if len(color) > 32:
        return form_error("color", "max length is 32")
    if color == "none" and not annotation_none_color_supported():
        return form_error("color", "unsupported before Readeck 0.22.2")

    if "note" in payload:
        if not annotation_notes_supported():
            return form_error("note", "unsupported before Readeck 0.22.2")
        if len(str(payload["note"])) > 1024:
            return form_error("note", "max length is 1024")

    return None


class MockReadeckHandler(BaseHTTPRequestHandler):
    server_version = "MockReadeck/0.1"

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/info":
            write_json(self, {"version": {"canonical": CONFIG["version"]}, "features": CONFIG["features"]})
            return
        if path == "/api/bookmarks":
            write_json(
                self,
                [
                    {
                        "id": ARTICLE_ID,
                        "title": "Runtime Probe Article",
                        "type": "article",
                        "created": "2026-05-06T00:00:00Z",
                        "read_progress": 37,
                        "labels": [],
                    }
                ],
            )
            return
        if path == "/api/bookmarks/%s/article.epub" % ARTICLE_ID:
            body = b"mock epub payload"
            self.send_response(200)
            self.send_header("Content-Type", "application/epub+zip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/bookmarks/%s/annotations" % ARTICLE_ID:
            write_json(self, [normalize_annotation(item) for item in STATE["annotations"]])
            return
        if path == "/__state":
            write_json(self, STATE)
            return
        write_json(self, {"error": "not_found", "path": path}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        payload = request_payload(self)

        if path == "/api/oauth/client":
            error = validate_oauth_client(payload)
            if error:
                write_json(self, error, 400)
                return
            STATE["oauth_clients"].append(payload)
            write_json(self, {"client_id": "mock-client"})
            return
        if path == "/api/oauth/device":
            write_json(
                self,
                {
                    "device_code": "mock-device",
                    "user_code": "ABCD1234",
                    "verification_uri": "http://127.0.0.1/device",
                    "verification_uri_complete": "http://127.0.0.1/device?user_code=ABCD1234",
                    "interval": 5,
                    "expires_in": 300,
                },
            )
            return
        if path == "/api/oauth/token":
            STATE["oauth_token_requests"] += 1
            write_json(self, {"access_token": "oauth-access", "refresh_token": "oauth-refresh", "expires_in": 3600})
            return
        if path == "/api/bookmarks/%s/annotations" % ARTICLE_ID:
            error = validate_annotation(payload)
            if error:
                write_json(self, error, 422)
                return
            annotation_id = "created-%d" % (len(STATE["annotation_posts"]) + 1)
            payload["id"] = annotation_id
            STATE["annotation_posts"].append(payload)
            STATE["annotations"].append(normalize_annotation(payload))
            write_json(self, normalize_annotation(payload), 201)
            return
        write_json(self, {"error": "not_found", "path": path}, 404)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--version", default="0.22.2")
    parser.add_argument("--features", default="oauth")
    args = parser.parse_args()
    CONFIG["version"] = args.version
    CONFIG["features"] = [item.strip() for item in args.features.split(",") if item.strip()]
    server = ThreadingHTTPServer((args.host, args.port), MockReadeckHandler)
    print("Mock Readeck listening on http://%s:%s" % (args.host, args.port), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
