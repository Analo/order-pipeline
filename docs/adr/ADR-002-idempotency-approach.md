# ADR-002: Hand-rolled idempotency over Lambda Powertools @idempotent

**Status:** Accepted  
**Date:** 2026-10-21  
**Author:** Analo Nelson

---

## Context

SQS delivers messages **at least once** — under failure scenarios (Lambda timeout, network partition, partial batch failure), the same `orderId` may arrive at the processor more than once. Without an idempotency guard, a duplicate delivery would write the same order twice to DynamoDB, producing phantom records and incorrect inventory/billing signals.

Two approaches are viable: **AWS Lambda Powertools** `@idempotent` decorator, or a **hand-rolled DynamoDB conditional write**.

---

## Decision

Use a **hand-rolled DynamoDB conditional write**:

```python
TABLE.put_item(
    Item={...},
    ConditionExpression="attribute_not_exists(orderId)",
)
```

If `orderId` already exists, DynamoDB raises `ConditionalCheckFailedException`. The processor catches this, logs `IDEMPOTENCY_HIT`, and returns without re-raising — the message is deleted from SQS normally.

---

## Rationale

### Why not Lambda Powertools @idempotent?

The Powertools `@idempotent` decorator is excellent in production — it handles in-progress locks, expiry, and multiple event types. But it introduces an invisible mechanism: a separate DynamoDB idempotency table, a lock record per invocation, and a TTL-based expiry window. For a portfolio project meant to demonstrate architectural understanding, hiding the mechanism inside a decorator obscures the very concept being demonstrated.

**The goal here is to make the mechanism explicit and visible:**
- The `ConditionExpression` is readable in the handler.
- The `ConditionalCheckFailedException` catch is a specific, traceable code path.
- The `IDEMPOTENCY_HIT` log line is a concrete evidence artifact.
- A reviewer can follow the idempotency path without reading any external library code.

### Why DynamoDB conditional write is sufficient here

| Property | Required? | Met? |
|---|---|---|
| Duplicate write prevention | Yes | Yes — ConditionalCheckFailed stops the PutItem |
| In-progress lock (prevent concurrent dupes) | No | Not needed — SQS delivers to one consumer at a time per message |
| Idempotency across different Lambda invocations | Yes | Yes — orderId is the DynamoDB hash key |
| Separate idempotency store | No | No — orders table doubles as the idempotency store |

The SQS-to-Lambda trigger delivers each message to **one** Lambda instance at a time. Concurrent delivery of the same message to two Lambda instances is not possible with standard SQS queues. Therefore, in-progress locking (which Powertools provides) is unnecessary here.

### Cost

The conditional write uses the same `PutItem` call that already writes the order. There is no additional DynamoDB table, no extra read unit, no TTL management. The idempotency mechanism has zero incremental cost.

---

## Trade-offs and What We Gave Up

- **No in-progress lock.** If this were migrated to a Kinesis source or a pattern where the same event could be delivered to two Lambdas simultaneously, the hand-rolled approach would not prevent a race condition. Powertools handles this. Document this assumption clearly if the consumer topology changes.
- **No automatic expiry of idempotency records.** Powertools stores idempotency records in a separate table with a TTL. Here, the idempotency record IS the order record — it expires via the `expiresAt` TTL on the orders table. This is simpler but couples idempotency lifetime to order record lifetime.
- **Single-key idempotency only.** This approach uses `orderId` as the idempotency key. If a future requirement needed idempotency on a composite key (e.g., `orderId + retryAttempt`), the conditional expression would need to be extended.

---

## Evidence of the Mechanism Working

After running `scripts/seed_orders.py`, CloudWatch Logs for the processor Lambda will show:

```
OK orderId=<uuid>
OK orderId=<uuid>
...
IDEMPOTENCY_HIT orderId=<uuid> — duplicate skipped
IDEMPOTENCY_HIT orderId=<uuid> — duplicate skipped
IDEMPOTENCY_HIT orderId=<uuid> — duplicate skipped
```

The `IDEMPOTENCY_HIT` lines confirm that the conditional write fired and was caught — proving the mechanism works without a test framework. See `docs/evidence/idempotency_proof.md`.
