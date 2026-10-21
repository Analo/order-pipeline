# Order Pipeline — Event-Driven Order Processing on AWS

An order placed in an e-commerce system must survive infrastructure failures, duplicate deliveries, and sudden traffic spikes — and still reach the database exactly once. This project builds and instruments that guarantee end-to-end using AWS serverless primitives.

**Business outcome:** Orders are never lost, never double-counted, and failures are visible within 60 seconds via CloudWatch alarms.

---

## Architecture

```
Caller
  │
  │  POST /orders
  ▼
API Gateway (REST)
  │
  │  Lambda proxy
  ▼
Validator Lambda ─── 400 Bad Request ──► Caller
  │  (Python 3.12)         ▲
  │  - Validates schema     │ invalid
  │  - Enriches with        │ (never touches SQS)
  │    receivedAt ──────────┘
  │
  │  sqs:SendMessage
  ▼
SQS Source Queue  ◄──── replay_dlq.py (manual)
  │                            ▲
  │  (at-least-once)           │
  ▼                            │
Processor Lambda         SQS DLQ (Dead Letter Queue)
  │  (Python 3.12)             ▲
  │  - DynamoDB PutItem        │ maxReceiveCount = 3
  │  - ConditionExpression ────┘ (message moved after 3 failures)
  │    attribute_not_exists(orderId)
  │    → idempotency guarantee
  ▼
DynamoDB (orders table)
  - Hash key: orderId
  - TTL: expiresAt (7 days)

Monitoring (CloudWatch)
  - Alarm: DLQ depth > 0 → SNS → Email
  - Alarm: Processor errors
  - Alarm: Validator errors
  - Alarm: Processor throttles
  - Dashboard: DLQ, Lambda, DynamoDB metrics
```

---

## Key Design Decisions

| Decision | Choice | Why |
|---|---|---|
| Queue | SQS not Kinesis | Orders are independent; no cross-order ordering needed. SQS costs $0 at zero traffic. Kinesis minimum ~$11/month. See [ADR-001](docs/adr/ADR-001-sqs-vs-kinesis.md) |
| Idempotency | Hand-rolled DynamoDB conditional write | Makes the mechanism explicit and reviewable. `ConditionExpression="attribute_not_exists(orderId)"` is one line; no external library required. See [ADR-002](docs/adr/ADR-002-idempotency-approach.md) |
| Batch failure | `ReportBatchItemFailures` | Lambda reports individual failed message IDs so SQS retries only those, not the whole batch |
| Poison pill | `bisect_batch_on_function_error=true` | On a batch error, Lambda splits the batch in half and retries — isolates the bad message in O(log n) retries |
| Validator rejects bad input | Before SQS, not after | Keeps DLQ signal clean: DLQ entries mean processor failures, not bad caller input |

---

## Evidence Artifacts

After running the seed script against a deployed environment, three evidence files demonstrate the pipeline working as designed:

| File | What it proves |
|---|---|
| `docs/evidence/seed_orders.log` | API responses: 5× 202 (valid), 4× 400 (malformed rejected), 3× 202 (duplicates accepted by API) |
| `docs/evidence/dlq_transcript.log` | DLQ empty after seeding — malformed orders were blocked at the validator, not the processor |
| `docs/evidence/idempotency_proof.md` | CloudWatch Logs showing `IDEMPOTENCY_HIT` for the 3 duplicate orders; DynamoDB showing exactly 5 records |

---

## What-If Scenarios

**What if the processor Lambda crashes mid-batch?**  
SQS retries the unacknowledged messages. `bisect_batch_on_function_error=true` splits the batch to isolate the offending message. After `maxReceiveCount` attempts, the message moves to the DLQ and an alarm fires.

**What if the same orderId arrives twice?**  
The DynamoDB conditional write (`attribute_not_exists(orderId)`) raises `ConditionalCheckFailedException` on the duplicate. The processor catches it, logs `IDEMPOTENCY_HIT`, and returns cleanly — the message is deleted from SQS. No duplicate record, no error, no alarm.

**What if DynamoDB is temporarily unavailable?**  
The `put_item` call raises a `ClientError` that is not caught by the idempotency handler. It propagates to the outer `except Exception`, appending the `messageId` to `batchItemFailures`. SQS retries that message on the next poll cycle.

**What if traffic spikes 100×?**  
SQS buffers messages; the processor Lambda scales concurrently (one instance per message batch, up to the account Lambda concurrency limit). DynamoDB on `PAY_PER_REQUEST` scales automatically. No pre-provisioning required.

**What if we need ordering guarantees in the future?**  
Switch to an SQS FIFO queue with `MessageGroupId=customerId`. Orders within a customer group would then be strictly ordered. The cost increases slightly (FIFO pricing), and `MessageDeduplicationId` would replace the DynamoDB conditional write for deduplication.

---

## Project Structure

```
order-pipeline/
├── terraform/
│   ├── main.tf                     # Root module wiring
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── terraform.tfvars.example    # Copy → terraform.tfvars
│   ├── backend.hcl.example         # Copy → backend.hcl
│   └── modules/
│       ├── queues/      # SQS source queue + DLQ
│       ├── processor/   # DynamoDB + processor Lambda
│       ├── api/         # API Gateway + validator Lambda
│       └── monitoring/  # CloudWatch alarms + dashboard + SNS
├── lambda/
│   ├── validator/handler.py        # Schema validation → SQS
│   └── processor/handler.py        # DynamoDB conditional write
├── scripts/
│   ├── seed_orders.py              # Generate evidence artifacts
│   ├── replay_dlq.py               # Replay failed messages
│   └── health_check.sh             # Post-deploy smoke test
├── docs/
│   ├── adr/
│   │   ├── ADR-001-sqs-vs-kinesis.md
│   │   └── ADR-002-idempotency-approach.md
│   └── evidence/                   # Populated after running seed script
└── .github/workflows/
    ├── terraform-plan.yml          # Runs on PRs
    ├── terraform-apply.yml         # Manual trigger only
    └── security-scan.yml           # Checkov + Bandit
```

---

## Deploy

### Prerequisites

- AWS CLI configured (`aws configure --profile azarous`)
- Terraform >= 1.9
- Python 3.12
- An S3 bucket for Terraform state

### Steps

```bash
# 1. Clone and configure
git clone https://github.com/Analo/order-pipeline.git
cd order-pipeline

# 2. Set up Terraform backend and variables
cp terraform/backend.hcl.example terraform/backend.hcl
# Edit backend.hcl with your S3 bucket name

cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Init, plan, apply
cd terraform
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# 4. Smoke test
API_ENDPOINT=$(terraform output -raw api_endpoint)
../scripts/health_check.sh "$API_ENDPOINT"

# 5. Seed and generate evidence artifacts
cd ..
pip install requests
python scripts/seed_orders.py --endpoint "$API_ENDPOINT" | tee docs/evidence/seed_orders.log

# 6. Destroy when done (cost control)
cd terraform
terraform destroy -var-file=terraform.tfvars
```

---

## Cost Profile

Designed to run at near-zero cost during testing:

| Service | Cost |
|---|---|
| SQS | $0 at zero traffic; $0.40/million requests |
| Lambda | Free tier: 1M req/month, 400K GB-seconds |
| DynamoDB | $0 at zero traffic (PAY_PER_REQUEST) |
| CloudWatch | Free tier covers basic metrics and alarms |
| API Gateway | Free tier: 1M REST API calls/month |

**Total for a demo run (~100 orders):** < $0.01

---

## Tech Stack

AWS: API Gateway REST · Lambda (Python 3.12) · SQS · DynamoDB · CloudWatch · SNS  
IaC: Terraform 1.9 (modular) · S3 backend  
CI/CD: GitHub Actions · Checkov · Bandit
