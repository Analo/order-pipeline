# Idempotency Proof

**Date:** 2026-10-23  
**Account:** 437628027223 | **Region:** eu-west-1  
**Table:** order-pipeline-dev-orders

---

## What was tested

The seed script sent 3 orders a second time with the **same orderId** as the first batch.
SQS at-least-once delivery guarantees this scenario will happen in production — this test
simulates it deliberately.

---

## DynamoDB — 6 unique records (no duplicates written)

```
Total records: 6

orderId=smoke-1792749058…  customer=smoke-test   amount=1
orderId=6c7cc7b5-9829-4b…  customer=cust-001     amount=149.97
orderId=d2db939e-3479-4d…  customer=cust-002     amount=29.99
orderId=655dac17-12be-4f…  customer=cust-003     amount=89.98
orderId=ba6b6224-61e8-45…  customer=cust-001     amount=59.98
orderId=7cb65ac0-6360-42…  customer=cust-004     amount=199.95
```

9 messages entered SQS. Only 6 unique records exist in DynamoDB.
The 3 duplicate orderIds produced no new rows.

---

## CloudWatch Logs — IDEMPOTENCY_HIT for all 3 duplicates

```
[INFO] 2026-10-23T09:54:29.427Z  IDEMPOTENCY_HIT orderId=655dac17-12be-4f2d-8e00-1a209c8a6c16 — duplicate skipped
[INFO] 2026-10-23T09:54:40.423Z  IDEMPOTENCY_HIT orderId=6c7cc7b5-9829-4b83-9ea0-edc7fa466c97 — duplicate skipped
[INFO] 2026-10-23T09:54:40.432Z  IDEMPOTENCY_HIT orderId=d2db939e-3479-4d83-97f2-d7b478c89c42 — duplicate skipped
```

---

## How it works

The processor Lambda uses a DynamoDB conditional write:

```python
TABLE.put_item(
    Item={...},
    ConditionExpression="attribute_not_exists(orderId)",
)
```

When `orderId` already exists, DynamoDB raises `ConditionalCheckFailedException`.
The Lambda catches it, logs `IDEMPOTENCY_HIT`, and returns without re-raising.
SQS treats this as a successful message processing and deletes the message — no
retry, no DLQ entry.

**Result:** Every order is written exactly once, regardless of how many times
SQS delivers the same message.
