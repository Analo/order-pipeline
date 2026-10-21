"""
Order processor Lambda.

Triggered by SQS. Writes each order to DynamoDB using a conditional PutItem
so that duplicate deliveries (SQS at-least-once) are handled gracefully.

Idempotency pattern:
  PutItem with ConditionExpression="attribute_not_exists(orderId)"
  → If the orderId already exists, DynamoDB raises ConditionalCheckFailedException.
  → We catch it, log an idempotency hit, and return without failing the message.
  → The message is deleted from SQS normally — no retry, no DLQ entry.

Batch failure reporting:
  Returns {"batchItemFailures": [...]} so SQS retries only the individual
  messages that failed, not the whole batch. Combined with bisect_batch_on_
  function_error=true, this prevents one poison pill from blocking all others.
"""

import json
import logging
import os
from datetime import datetime, timezone, timedelta

import boto3
from botocore.exceptions import ClientError
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE = dynamodb.Table(os.environ["ORDERS_TABLE"])
TTL_DAYS = int(os.environ.get("TTL_DAYS", "7"))


def lambda_handler(event, context):
    batch_item_failures = []

    for record in event["Records"]:
        message_id = record["messageId"]
        try:
            _process_record(record)
        except Exception as exc:
            logger.error("ERROR messageId=%s: %s", message_id, exc, exc_info=True)
            batch_item_failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": batch_item_failures}


def _process_record(record: dict) -> None:
    body = json.loads(record["body"])
    order_id = body["orderId"]

    expires_at = int(
        (datetime.now(timezone.utc) + timedelta(days=TTL_DAYS)).timestamp()
    )

    try:
        TABLE.put_item(
            Item={
                "orderId": order_id,
                "customerId": body.get("customerId"),
                "items": body.get("items", []),
                # DynamoDB does not support float; Decimal is the correct type.
                "totalAmount": Decimal(str(body.get("totalAmount", 0))),
                "receivedAt": body.get("receivedAt"),
                "processedAt": datetime.now(timezone.utc).isoformat(),
                "expiresAt": expires_at,
            },
            ConditionExpression="attribute_not_exists(orderId)",
        )
        logger.info("OK orderId=%s", order_id)

    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            # Duplicate delivery — order was already written on a previous attempt.
            # Log and skip; do NOT re-raise, so the message is deleted from SQS.
            logger.info("IDEMPOTENCY_HIT orderId=%s — duplicate skipped", order_id)
        else:
            raise
