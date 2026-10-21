#!/usr/bin/env python3
"""
Replay messages from the Dead Letter Queue back to the source queue.

Use this after investigating and fixing the root cause of failures.
Each replayed message is deleted from the DLQ to prevent double-processing.

Usage:
    python scripts/replay_dlq.py \\
        --dlq-url  https://sqs.eu-west-1.amazonaws.com/ACCOUNT/order-pipeline-dev-dlq \\
        --source-url https://sqs.eu-west-1.amazonaws.com/ACCOUNT/order-pipeline-dev-orders \\
        --profile azarous

    # Get queue URLs from Terraform output:
    terraform -chdir=terraform output -json | jq '{dlq: .dlq_url.value, src: .source_queue_url.value}'
"""

import argparse
import json
import sys

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def main() -> None:
    parser = argparse.ArgumentParser(description="Replay DLQ messages to the source queue.")
    parser.add_argument("--dlq-url",    required=True, help="Dead Letter Queue URL")
    parser.add_argument("--source-url", required=True, help="Source queue URL")
    parser.add_argument("--max-messages", type=int, default=100, help="Max messages to replay")
    parser.add_argument("--dry-run",    action="store_true", help="Print messages without moving them")
    parser.add_argument("--profile",    default=None, help="AWS CLI profile name")
    args = parser.parse_args()

    session = boto3.Session(profile_name=args.profile)
    sqs = session.client("sqs")

    replayed = 0
    print(f"{'[DRY RUN] ' if args.dry_run else ''}Replaying from DLQ → source queue…\n")

    while replayed < args.max_messages:
        try:
            resp = sqs.receive_message(
                QueueUrl=args.dlq_url,
                MaxNumberOfMessages=min(10, args.max_messages - replayed),
                WaitTimeSeconds=5,
                AttributeNames=["ApproximateReceiveCount"],
            )
        except (BotoCoreError, ClientError) as exc:
            print(f"ERROR receiving from DLQ: {exc}", file=sys.stderr)
            sys.exit(1)

        messages = resp.get("Messages", [])
        if not messages:
            print("DLQ is empty — nothing left to replay.")
            break

        for msg in messages:
            receive_count = msg.get("Attributes", {}).get("ApproximateReceiveCount", "?")
            body_preview = msg["Body"][:80].replace("\n", " ")
            print(f"  [{replayed + 1:03d}] id={msg['MessageId'][:16]}… receiveCount={receive_count}  {body_preview}")

            if not args.dry_run:
                try:
                    sqs.send_message(QueueUrl=args.source_url, MessageBody=msg["Body"])
                    sqs.delete_message(QueueUrl=args.dlq_url, ReceiptHandle=msg["ReceiptHandle"])
                except (BotoCoreError, ClientError) as exc:
                    print(f"    ERROR moving message: {exc}", file=sys.stderr)
                    continue

            replayed += 1

    action = "inspected" if args.dry_run else "replayed"
    print(f"\n{action.capitalize()} {replayed} message(s).")


if __name__ == "__main__":
    main()
