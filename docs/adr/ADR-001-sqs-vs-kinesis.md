# ADR-001: SQS over Kinesis for order queuing

**Status:** Accepted  
**Date:** 2026-10-21  
**Author:** Analo Nelson

---

## Context

The order pipeline needs a durable buffer between the API layer and the processor Lambda. Two AWS services are candidates: **Amazon SQS** (simple queue) and **Amazon Kinesis Data Streams** (ordered event stream).

The key characteristics of this workload:
- Each order is independent — no ordering guarantee is required *across* orders.
- Traffic is bursty and variable; at zero traffic, cost should be zero.
- Failure isolation matters: one bad order must not block others.
- The team is small; operational complexity should be kept low.

---

## Decision

Use **Amazon SQS** with a Dead Letter Queue.

---

## Rationale

| Dimension | SQS | Kinesis |
|---|---|---|
| **Ordering** | Per-message (no cross-message guarantee) | Per-shard (strict ordering within a shard) |
| **Cost at zero traffic** | $0 | ~$0.015/shard-hour ≈ $11/month minimum |
| **Failure isolation** | DLQ: failed messages move independently | All consumers on a shard block behind a bad record |
| **Scaling** | Automatic, no shard management | Manual shard splits/merges |
| **Replay** | Manual via replay_dlq.py | Built-in retention window + iterator |
| **Operational burden** | Low | Shard monitoring, resharding operations |

**Why ordering doesn't matter here:** Orders are processed independently by orderId. Even if `order-B` is processed before `order-A`, neither outcome affects the other. Kinesis's shard-level ordering is only valuable when events within a partition have a causal relationship (e.g., state machine transitions for the same entity).

**Why DLQ beats Kinesis's blocking behaviour:** With SQS + DLQ, a poison-pill message moves to the DLQ after `maxReceiveCount` attempts and processing continues for all other messages. With Kinesis, an iterator stuck on a bad record blocks the entire shard until the record is past its retention window or the iterator is manually advanced.

**Why cost matters:** This pipeline must scale to zero at zero traffic. A Kinesis stream with a minimum of one shard costs ~$11/month even idle. SQS charges per API call — at zero traffic, cost is exactly $0.

---

## Trade-offs and What We Gave Up

- **No cross-order sequence guarantee.** If future requirements need "process all orders for customer X in submission order", SQS cannot guarantee that without additional application-level sequencing (e.g., per-customer state machine in DynamoDB). This is not a current requirement.
- **At-least-once delivery.** SQS may deliver a message more than once. The processor handles this via DynamoDB conditional writes (see ADR-002).
- **No built-in replay window.** Kinesis retains all records for 1–7 days for reprocessing. SQS messages are deleted after delivery. We compensate with `replay_dlq.py` for DLQ replay, but replay of successfully processed messages is not supported. This is acceptable for the current use case.

---

## Alternatives Rejected

- **Kinesis Data Streams:** Over-engineered for per-order-independent processing; minimum cost even at zero traffic.
- **EventBridge:** Higher latency, schema registry overhead, no DLQ equivalent. Better fit for fan-out to multiple consumers.
- **Direct Lambda invocation from API Gateway:** No durability; if the processor fails, the order is lost. No retry mechanism.
