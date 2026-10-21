"""
Order validator Lambda.

Sits behind API Gateway (Lambda proxy integration). Validates the incoming
order, rejects bad input with 400 before it reaches the queue, and forwards
valid orders to SQS with a 202 response.

Rejecting at this layer keeps the DLQ signal clean: messages only land in the
DLQ when the *processor* fails (infrastructure or code error), not when a
caller submits a malformed payload.
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["SOURCE_QUEUE_URL"]

REQUIRED_FIELDS = {"orderId", "customerId", "items", "totalAmount"}


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Request body must be valid JSON"})

    if not isinstance(body, dict):
        return _response(400, {"error": "Request body must be a JSON object"})

    missing = REQUIRED_FIELDS - body.keys()
    if missing:
        return _response(400, {"error": f"Missing required fields: {sorted(missing)}"})

    if not isinstance(body.get("items"), list) or len(body["items"]) == 0:
        return _response(400, {"error": "items must be a non-empty list"})

    try:
        amount = float(body["totalAmount"])
        if amount <= 0:
            raise ValueError
    except (ValueError, TypeError):
        return _response(400, {"error": "totalAmount must be a positive number"})

    if not isinstance(body.get("orderId"), str) or not body["orderId"].strip():
        return _response(400, {"error": "orderId must be a non-empty string"})

    body["receivedAt"] = datetime.now(timezone.utc).isoformat()

    try:
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(body))
    except ClientError as exc:
        logger.error("Failed to enqueue order %s: %s", body["orderId"], exc)
        return _response(503, {"error": "Failed to enqueue order — please retry"})

    logger.info("QUEUED orderId=%s customerId=%s", body["orderId"], body["customerId"])
    return _response(202, {"orderId": body["orderId"], "status": "queued"})


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
