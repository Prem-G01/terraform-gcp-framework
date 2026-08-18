"""Unit tests for the process-upload Cloud Function — runs entirely local,
no GCP call. Calls `process_upload` directly with a real flask.Request
built via `test_request_context` (functions_framework.http's wrapper is a
pure passthrough, so this exercises exactly what the real runtime calls).

Run: pytest functions/process-upload/test_main.py -v
"""

import flask
import pytest

from main import process_upload

app = flask.Flask(__name__)


def _call(**json_body):
    with app.test_request_context("/", method="POST", json=json_body):
        return process_upload(flask.request)


def _call_raw(data, content_type):
    with app.test_request_context("/", method="POST", data=data, content_type=content_type):
        return process_upload(flask.request)


def test_valid_payload_is_accepted():
    body, status = _call(bucket="my-bucket", name="uploads/file.png", contentType="image/png")
    assert status == 200
    assert body.get_json() == {"status": "accepted", "bucket": "my-bucket", "name": "uploads/file.png"}


def test_missing_bucket_is_rejected():
    body, status = _call(name="uploads/file.png")
    assert status == 400
    assert "error" in body.get_json()


def test_missing_body_is_rejected():
    body, status = _call_raw("not json", "text/plain")
    assert status == 400
