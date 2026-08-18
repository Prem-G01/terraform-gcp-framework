"""HTTP Cloud Function: process-upload.

modules/compute/cloudfunctions only deploys HTTP-triggered 2nd-gen
functions (see that module's main.tf — no event_trigger block yet), so
this expects to be called directly with the same JSON shape a Cloud
Storage "object finalized" notification carries, rather than being wired
to a native Storage trigger. If you need a real Storage-triggered
function, `modules/compute/cloudfunctions` needs an event_trigger block
added first — see docs/modules.md.

Deployed from a zip built by `python -m engine.cli build-function-source`
(see docs/modules.md "Building and uploading Cloud Function source").
"""

import functions_framework
from flask import jsonify


@functions_framework.http
def process_upload(request):
    payload = request.get_json(silent=True) or {}
    bucket = payload.get("bucket")
    name = payload.get("name")
    content_type = payload.get("contentType", "unknown")

    if not bucket or not name:
        return jsonify({"error": "expected JSON body with 'bucket' and 'name'"}), 400

    # Real processing (virus scan, thumbnail generation, indexing, ...)
    # goes here. This is intentionally a minimal, honest placeholder — see
    # docs/troubleshooting.md for why this function shipped disabled until
    # real source existed.
    print(f"process-upload: received {bucket}/{name} ({content_type})")

    return jsonify({"status": "accepted", "bucket": bucket, "name": name}), 200
