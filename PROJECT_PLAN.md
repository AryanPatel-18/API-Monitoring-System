# Scheduled HTTP Health Monitoring Service - Architecture & Implementation Blueprint

## 1. Project Definition

The **Scheduled HTTP Health Monitoring Service** is an API-first backend built in Go. Authenticated users register public HTTP endpoints, define how often they should be checked, and retrieve historical health and latency data for those endpoints.

The system is not just a one-off API tester. Its main purpose is to run repeated checks safely, store useful diagnostics, and remain correct when multiple application instances are running at the same time.

### 1.1. Primary Product Outcome

The first version of the project must prove these core capabilities:

- Users can register and authenticate.
- Users can create monitored endpoints with URL, method, headers, body, and check interval.
- Active endpoints are checked automatically on a schedule.
- Each execution stores success/failure, status code, total latency, and network timing breakdowns.
- Multiple app instances do not process the same endpoint at the same time.
- Old raw history is pruned so the database stays usable over time.

### 1.2. What This Project Is Optimized For

- **Reliable scheduled execution:** checks continue without duplicate processing.
- **Operational clarity:** logs, metrics, and traces make failures debuggable.
- **Strict boundaries:** HTTP handlers, services, repositories, workers, and the pinger have separate responsibilities.
- **Write-heavy safety:** the schema and background jobs are designed for constant inserts.
- **Incremental delivery:** each stage produces a usable foundation for the next stage.

### 1.3. End-to-End System Flow

This is the system flow you should keep in mind while building:

1. A user registers and logs in.
2. The user creates an endpoint to monitor.
3. The endpoint is stored as active with an initial `next_check_at`.
4. A scheduler loop claims due endpoints using PostgreSQL row locking.
5. Workers execute the outbound HTTP request through a pure `pinger` package.
6. The worker stores the result in `test_results`.
7. The worker updates the endpoint's scheduling state and clears its lock.
8. Read APIs return the endpoint's current status plus historical results.

## 2. Technical Stack & Infrastructure

The system is designed as an API-first backend, adhering to clean architecture principles and interface-driven design.

### 2.1. Core Application

- **Language:** Go (1.21+) - Chosen for lightweight goroutines and built-in concurrency primitives.
- **Router:** `go-chi/chi/v5` - Idiomatic, standard-library compatible routing with strong middleware support.
- **Logging:** `log/slog` - Structured JSON logging for machine-readable output.
- **Validation:** `go-playground/validator/v10` - Struct-tag based request validation.

### 2.2. Data Persistence & State

- **Primary Database:** PostgreSQL 16 (containerized) - Handles relational data, strict schema enforcement, and queue locking.
- **Database Driver:** `jackc/pgx/v5` - High-performance Postgres driver with pooling support.
- **Query Builder:** `sqlc` - Compiles raw SQL into type-safe Go code.
- **Migrations:** `pressly/goose` - SQL-based schema evolution.
- **Caching:** None initially. Skip external caching in the first version and only add a small in-process TTL cache later if a specific read path proves hot.

### 2.3. Observability & Security

- **Authentication:** Stateless JWTs (HMAC-SHA256), with `bcrypt` for password hashing.
- **Metrics:** `prometheus/client_golang` - Exposes `/metrics` for scraping system health.
- **Tracing:** OpenTelemetry (`go.opentelemetry.io/otel`) - Propagates trace IDs across requests and background jobs.

## 3. Directory Structure & Domain Boundaries

The application should remain a modular monolith. The point is not to create many folders for appearance; the point is to enforce rules about what each layer is allowed to know.

```text
ApiTester/
├── cmd/
│   └── api/                  # Application entry point, dependency wiring, server startup
├── internal/
│   ├── api/                  # HTTP transport layer
│   │   ├── handler/          # Request parsing, response formatting, status-code mapping
│   │   └── routes/           # Chi router configuration and route grouping
│   ├── auth/                 # JWT creation/parsing and password hashing helpers
│   ├── config/               # Environment loading and strongly typed config
│   ├── database/             # Postgres pool initialization
│   ├── middleware/           # Auth, rate limiting, metrics, logging, request ID
│   ├── models/               # Domain entities and transport DTOs
│   ├── pinger/               # Pure outbound HTTP execution and timing capture
│   ├── repository/           # SQL access layer and sqlc-generated queries
│   ├── services/             # Business rules, orchestration, authorization checks
│   └── worker/               # Scheduler loop, worker pool, retention jobs
├── migrations/               # Goose SQL migrations
├── scripts/                  # Development helpers
├── deployments/              # docker-compose.yml and container assets
└── docs/                     # OpenAPI notes, Postman collections, architecture docs
```

### 3.1. Boundary Rules You Should Not Break

- **`handler` knows HTTP, not SQL.**
  Handlers parse JSON, validate DTOs, call services, and map errors to HTTP responses.
- **`services` know business rules, not transport details.**
  Services should not depend on `http.Request`, `http.ResponseWriter`, or router state.
- **`repository` knows SQL, not business policy.**
  Repository methods should not decide quota, authorization, or status-code rules.
- **`pinger` knows outbound HTTP only.**
  It should not know about PostgreSQL, JWTs, or users.
- **`worker` knows background orchestration only.**
  It schedules jobs, runs the pinger, persists results, and updates state.
- **`middleware` remains request-scoped.**
  Background jobs must not depend on HTTP middleware context.

### 3.2. Recommended Package Contracts

- `internal/models`
  Keep request/response DTOs separate from persistence structs when fields differ.
- `internal/services`
  Prefer smaller interfaces by domain, such as user storage, endpoint storage, and result storage, instead of one large repository interface.
- `internal/worker`
  Keep the scheduler and worker execution separate. Claiming work and executing work are different concerns.

## 4. Delivery Strategy

Build the project in strict order. Do not jump to background workers before the synchronous flows, schema, and service boundaries are stable.

### 4.1. Recommended Build Order

1. Infrastructure bootstrap, configuration, schema, and observability.
2. Authentication and endpoint creation flow.
3. Pinger abstraction and synchronous read paths.
4. Scheduler, worker pool, and result persistence.
5. Retention and long-running safety hardening.

### 4.2. Rule for Advancing Between Stages

- Do not start the distributed worker pool until endpoint creation and retrieval work end to end.
- Do not start retention logic until raw result inserts are stable.
- Every stage should end with smoke checks that prove the system is ready for the next one.
- If a later requirement depends on missing data, change the schema early instead of trying to infer that data from large history scans later.

## 5. Implementation Phasing

### Stage 1: Infrastructure, Tooling & Observability

**Goal:** Establish a strict, debuggable foundation before writing business logic.

#### Outputs of This Stage

- Running a PostgreSQL container.
- Typed config loading with fail-fast startup behavior.
- Database bootstrap package.
- Initial migrations and generated `sqlc` code.
- HTTP server with health checks, metrics, request IDs, and structured logs.
- Optional lightweight in-process rate limiting on auth routes.

#### 1. Containerized Development Environment

The local environment should stay minimal at the start: Postgres for durable data, with no external cache or shared-state service until there is a concrete need.

- Create `deployments/docker-compose.yml`.
- Define a PostgreSQL 16 service on `5432`.
- Use a named Docker volume for Postgres so data survives container restarts.
- Keep container definitions simple and deterministic.

#### 2. Make Targets

You should avoid long manual commands during development. Add a `Makefile` with predictable targets such as:

- `db-up`
- `db-down`
- `migrate-up`
- `migrate-down`
- `sqlc-generate`
- `run`

The exact names can vary, but the important point is that booting the stack, applying migrations, generating queries, and starting the API are one-command actions.

#### 3. Configuration Contract

Centralize all environment loading in `internal/config`.

| Variable | Purpose |
| --- | --- |
| `PORT` | HTTP server port, default `8080` |
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET` | HMAC secret for JWT signing |

Implementation rules:

- Load environment once during startup.
- Parse raw environment values into a typed `Config` struct.
- Fail fast if a required value is missing or malformed.
- Do not call `os.Getenv` from random packages after this point.

#### 4. Database Bootstrap and Migrations

This stage should produce a database that can be recreated from zero at any time.

- Initialize Goose migrations in `migrations/`.
- In the first migration, enable the extension required for UUID generation:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

- Create the base tables and indexes described in Section 7.
- Add `sqlc` configuration that points to migrations and query files.
- Generate typed query code into `internal/repository/`.

At this stage, the minimum useful query set is:

- Create user
- Get user by email
- Create endpoint
- List endpoints for a user
- Get endpoint by ID and user ID
- Claim due endpoints for the scheduler
- Insert test result
- Update endpoint state after a check
- Prune old test results

#### 5. Application Bootstrap and Observability

`cmd/api/main.go` should become the single place where the application is wired together.

- Load config.
- Initialize the `slog` logger.
- Open the Postgres connection.
- Build the router.
- register `/health`.
- register `/metrics`.
- install request ID middleware.
- install request logging middleware.
- support graceful shutdown on `SIGINT` and `SIGTERM`.

The goal here is simple: every request should be traceable, and startup failures should be obvious.

#### 6. Lightweight Auth Rate Limiting

Brute-force protection matters, but it does not need distributed coordination on day one.

- If you add rate limiting in Stage 1, keep it simple and in-process for:
  - `POST /v1/auth/register`
  - `POST /v1/auth/login`
- Keep the scope narrow at first: per-IP limits on auth routes only.
- If it slows down delivery, defer it until after the core auth flow works end to end.

#### Stage 1 Exit Criteria

Do not leave Stage 1 until all of these are true:

- `docker compose` can start Postgres locally.
- Migrations run successfully against an empty database.
- The API refuses to start when required config is missing.
- `/health` returns `200`.
- `/metrics` is exposed.
- Request logs include a request ID.

### Stage 2: Synchronous Services & Clean Abstractions

**Goal:** Build the synchronous user flows and the core domain rules before introducing background execution.

#### Outputs of This Stage 0

- Registration and login flow.
- JWT authentication middleware.
- Endpoint creation flow with strict validation and quotas.
- Endpoint retrieval and history retrieval flows.
- Pure `pinger` abstraction with timing capture.
- Service layer that can be unit-tested without a live database.
- Standardized JSON success and error responses.

#### 1. Domain Models and DTOs

Start by deciding which structs are domain-facing and which are transport-facing.

Recommended transport DTOs:

- `RegisterRequest`
- `LoginRequest`
- `CreateEndpointRequest`
- `EndpointResponse`
- `EndpointResultResponse`
- `ErrorResponse`

Recommended domain entities:

- `User`
- `Endpoint`
- `TestResult`

Important normalization rules:

- Store HTTP methods in uppercase.
- Preserve headers as key-value data.
- Treat `check_interval_minutes` as a validated integer, not a free-form string.

#### 2. Authentication Flow

Implement auth before endpoint management so every later route can assume a user identity is available.

`POST /v1/auth/register`

- Validate email and password presence.
- Hash the password with `bcrypt`.
- Insert the user.
- Return a safe response that never exposes the password hash.

`POST /v1/auth/login`

- Find the user by email.
- Compare the provided password with the stored hash.
- Issue an HMAC-signed JWT.

Auth middleware behavior:

- Read `Authorization: Bearer <token>`.
- Reject missing or malformed tokens with `401`.
- Put the authenticated `user_id` into request context for handlers and services.

Keep password policy minimal unless you explicitly decide to extend it later. The plan does not require advanced password rules beyond validation and secure storage.

#### 3. Repository Interfaces

The service layer should depend on interfaces, not on raw `sqlc` structs or database pools.

Use interfaces that reflect domain needs, for example:

- user store
- endpoint store
- result store

This keeps unit tests simple:

- handlers can be tested against mocked services
- services can be tested against mocked repositories
- repositories can be tested with integration tests against Postgres

#### 4. The Pinger Abstraction (`internal/pinger`)

The pinger is the core execution engine. Keep it pure.

Input contract:

- URL
- Method
- Headers
- Body
- Timeout

Output contract:

- HTTP status code
- total latency
- DNS lookup time
- TCP connection time
- TLS handshake time
- TTFB
- response size
- redirect count
- error message if the request fails before a valid response is completed

Implementation details:

- Use `net/http/httptrace` to capture DNS, TCP, TLS, and TTFB timings.
- Wrap execution in `context.WithTimeout`.
- Reuse an `http.Client` instead of building a new client per request.
- Read and discard the response body so you can measure bytes and allow connection reuse.

Behavioral rule:

- `total_latency_ms` should always be recorded, even on failures.
- If a response is never received, `status_code` should remain unset while `error_message` explains the failure.

#### 5. Endpoint Service Rules

The endpoint service owns the monitoring rules.

Validation and business constraints:

- Only allow `http://` and `https://` URLs.
- Enforce a maximum of 10 headers.
- Enforce a maximum request body size of 10KB.
- Default `method` to `GET` if omitted.
- Default `check_interval_minutes` to `5` if omitted.
- Treat `1` minute as the minimum interval.
- Treat `1440` minutes as the maximum interval.
- Enforce a maximum of 10 active endpoints per user.

Recommended creation behavior:

- Set `is_active = TRUE`.
- Set `next_check_at = NOW()` so a newly created endpoint can be picked up immediately.

Ownership rules:

- A user can only access or modify endpoints they own.
- Services should enforce this, not just handlers.

#### 6. API Handlers & Error Mapping

Handlers should be thin and predictable.

Handler responsibilities:

- Parse JSON once.
- Validate the DTO.
- Call the service.
- Map service errors to HTTP responses.
- Return JSON consistently.

Suggested error mapping:

- invalid request body or validation failure -> `400`
- invalid credentials -> `401`
- missing or invalid token -> `401`
- resource owned by another user -> `403`
- quota exceeded -> `403`
- record not found -> `404`
- duplicate email -> `409`
- unexpected internal failure -> `500`

Use one error envelope everywhere:

```json
{
  "error": {
    "code": "quota_exceeded",
    "message": "endpoint limit reached"
  }
}
```

#### 7. Read Paths Required Before Stage 3

Do not start the worker system until you can read back what was written.

At minimum, implement:

- a route to list the authenticated user's endpoints
- a route to fetch recent results for one endpoint

This is important because once workers are running, the fastest way to verify correct behavior is through these read APIs.

#### Stage 2 Exit Criteria

Stage 2 is complete only when:

- a user can register and log in
- JWT-protected routes work
- a user can create an endpoint
- invalid payloads return structured `400` responses
- a user can retrieve their endpoints and recent history
- services can be tested with mocked repositories
- the pinger has tests for success, timeout, and network failure scenarios

### Stage 3: Concurrency & the Distributed Worker Pool

**Goal:** Move scheduled checks out of synchronous request flow and into a crash-tolerant, distributed-safe background system.

#### Outputs of This Stage 1

- Scheduler loop that safely claims due endpoints.
- Worker pool for concurrent execution.
- Global outbound concurrency cap.
- Idempotent result persistence.
- Stale-lock recovery.
- Deterministic rescheduling and auto-disable behavior.

#### 1. Scheduler Design

The scheduler should run as a background goroutine started by the API process.

Recommended initial operating values:

- ticker interval: every `10` to `30` seconds
- claim batch size: `100`

The scheduler's job is only to claim work. It should not execute network requests itself.

#### 2. The Safe Claiming Query

The claim query must guarantee that multiple app instances do not take the same endpoint at the same time.

Use a Postgres query shaped like this:

```sql
WITH due AS (
    SELECT id
    FROM endpoints
    WHERE is_active = TRUE
      AND next_check_at <= NOW()
      AND (locked_at IS NULL OR locked_at < NOW() - INTERVAL '5 minutes')
    ORDER BY next_check_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT $1
)
UPDATE endpoints e
SET locked_at = NOW(),
    updated_at = NOW()
FROM due
WHERE e.id = due.id
RETURNING e.*;
```

Important behavior:

- `FOR UPDATE SKIP LOCKED` prevents duplicate claims across instances.
- stale locks are reclaimed using the `locked_at` cutoff.
- the scheduler commits quickly after claiming rows.

The single most important rule in this stage is this:

- **Never keep a database transaction open while performing the outbound HTTP request.**

Claim the row, commit, then do the network call outside the transaction.

#### 3. Dispatch Pipeline

After claiming rows:

- the scheduler pushes claimed endpoints into a buffered job channel
- a fixed worker pool consumes from that channel
- workers call the pinger and persist results

Use a global semaphore to cap concurrent outbound requests:

```go
sem := make(chan struct{}, 50)
```

This protects the process from opening too many outbound connections even if many jobs become due at once.

#### 4. Endpoint State Required for Worker Logic

The original schema needs a little more scheduling state to make worker behavior deterministic. These are not new product features; they are support fields for scheduling, read APIs, and auto-disable logic.

Add the following fields to `endpoints`:

- `consecutive_failures`
- `failing_since`
- `last_checked_at`
- `last_success_at`
- `last_status_code`
- `last_error_message`
- `last_total_latency_ms`

Why these fields matter:

- `consecutive_failures` drives backoff decisions.
- `failing_since` makes the 24-hour auto-disable rule easy to evaluate.
- `last_*` fields let list APIs show current state without scanning the entire `test_results` table.

#### 5. Worker Execution Flow

Each worker should follow the same deterministic sequence:

1. Receive a claimed endpoint.
2. Generate an `execution_id` for this run attempt.
3. Build the pinger request from the endpoint configuration.
4. Acquire the semaphore slot.
5. Execute the ping.
6. Release the semaphore slot.
7. Insert a row into `test_results`.
8. Update the endpoint's scheduling and summary fields.
9. Clear `locked_at`.

If the process crashes after claiming but before completion, the stale-lock rule ensures the endpoint becomes eligible again later.

#### 6. Success, Failure, and Rescheduling Rules

Define the success rule once and use it everywhere.

Recommended initial rule:

- treat `2xx` responses as success
- treat non-`2xx` responses and transport errors as failure

On success:

- set `is_success = TRUE`
- set `consecutive_failures = 0`
- set `failing_since = NULL`
- set `last_success_at = NOW()`
- clear `last_error_message`
- set `next_check_at = NOW() + check_interval_minutes`

On failure:

- set `is_success = FALSE`
- increment `consecutive_failures`
- if this is the first failure in the current streak, set `failing_since = NOW()`
- preserve `failing_since` for continued failures
- update `last_error_message`
- calculate the next run using backoff

Recommended backoff schedule:

- first failure -> `1 minute`
- second failure -> `5 minutes`
- third and later failures -> `15 minutes`

Apply this safely:

- never schedule later than needed for recovery
- never schedule earlier than the endpoint's normal interval if that interval is already larger

Practical rule:

- `next_check_at = NOW() + max(check_interval_minutes, backoff_for_failure_streak)`

#### 7. Auto-Disable Rule

If an endpoint remains in a failing state for 24 continuous hours:

- set `is_active = FALSE`
- clear `locked_at`

Use `failing_since` for this decision. That is more reliable than trying to infer continuous failure from raw history every time.

The original document mentioned a notification. Treat that as future work. Do not block the worker architecture on building notifications now.

#### 8. Idempotency and Write Safety

Each run attempt gets a unique `execution_id`.

- `test_results.execution_id` must be unique.
- if the same run attempt is accidentally retried, the unique constraint prevents duplicate result rows.
- if the final DB update fails after the HTTP request completed, the endpoint may stay locked until the stale-lock recovery window expires, which is acceptable and recoverable.

#### Stage 3 Exit Criteria

Stage 3 is complete only when:

- multiple app instances do not process the same endpoint simultaneously
- killing a worker process does not permanently orphan locked endpoints
- workers insert exactly one result row per execution attempt
- endpoint summary state reflects the latest run
- auto-disable after 24 hours of continuous failure works as defined

### Stage 4: Data Lifecycle & Retention

**Goal:** Keep the write-heavy history table from growing without bound while preserving useful recent data.

#### Outputs of This Stage 2

- retention policy for raw history
- pruning worker that deletes old rows in batches
- queries and indexes that still perform well after heavy write volume

#### 1. Retention Policy

Keep raw `test_results` rows for `30 days`.

That gives users recent diagnostic detail without allowing the time-series table to grow forever.

#### 2. Pruning Worker

Implement a low-priority background goroutine that runs once per hour.

Pruning rules:

- compute a cutoff: `NOW() - INTERVAL '30 days'`
- delete rows in batches of `5000`
- delete the oldest rows first
- sleep briefly between batches
- stop when a batch removes fewer than `5000` rows

Why batching matters:

- large deletes create long locks
- large deletes increase WAL churn
- large deletes compete with normal API and worker traffic

#### 3. Query Patterns to Protect

The retention logic should preserve the query patterns the product depends on:

- endpoint history query: `test_results(endpoint_id, checked_at DESC)`
- pruning query: `test_results(checked_at)`
- endpoint list query: read latest status from summary fields on `endpoints`, not from full history scans

#### 4. Future-Proofing Without Blocking MVP

Long-term daily aggregation is useful but should remain future work for now.

The retention worker can later gain a pre-delete hook that writes daily aggregates into a smaller summary table. Do not build that in the first version unless it becomes necessary.

#### Stage 4 Exit Criteria

Stage 4 is complete only when:

- rows older than 30 days are removed in small batches
- normal API traffic is not blocked by pruning
- endpoint history queries still use indexes efficiently
- the system can run for long periods without unbounded `test_results` growth

## 6. API Contracts & Validation Logic

API contracts should be explicit enough that handler behavior, service rules, and schema constraints all point in the same direction.

### 6.1. Common API Rules

- Use JSON request and response bodies.
- Use `Authorization: Bearer <token>` for protected routes.
- Return a consistent error envelope.
- Never expose internal SQL errors or stack traces to clients.

Standard error response:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "url must use http or https"
  }
}
```

### 6.2. `POST /v1/auth/register`

Purpose:

- Create a new user account.

Request body:

- `email` (required)
- `password` (required)

Validation rules:

- email must be present and syntactically valid
- password must be present

Expected behavior:

- hash password with `bcrypt`
- reject duplicate emails
- return a safe user payload or other agreed auth response

### 6.3. `POST /v1/auth/login`

Purpose:

- Authenticate an existing user and return a JWT.

Request body:

- `email` (required)
- `password` (required)

Expected behavior:

- reject unknown email or incorrect password with `401`
- return a signed JWT on success

### 6.4. `POST /v1/endpoints`

Purpose:

- Register an endpoint for scheduled monitoring.

Request body:

- `name` (required, string)
- `url` (required, string)
- `method` (optional, string, default `GET`)
- `check_interval_minutes` (optional, integer, default `5`)
- `headers` (optional, JSON object)
- `body` (optional, string)

Validation rules:

- `url` must use `http` or `https`
- `method` must be one of `GET`, `POST`, `PUT`, `PATCH`, `DELETE`
- `check_interval_minutes` must be between `1` and `1440`
- `headers` may contain at most `10` key-value pairs
- `body` may contain at most `10240` characters

Recommended response fields:

- `id`
- `name`
- `url`
- `method`
- `check_interval_minutes`
- `is_active`
- `next_check_at`
- `created_at`

### 6.5. `GET /v1/endpoints`

Purpose:

- Return the authenticated user's endpoints with current summary state.

Response should preferably include fields already stored on `endpoints`, such as:

- `last_checked_at`
- `last_status_code`
- `last_error_message`
- `last_total_latency_ms`
- `consecutive_failures`
- `is_active`
- `next_check_at`

This avoids expensive "latest result" joins for every row in the list.

### 6.6. `GET /v1/endpoints/{id}/results`

Purpose:

- Return recent historical results for one endpoint owned by the authenticated user.

Behavior:

- order by `checked_at DESC`
- start with a simple `limit` parameter
- add more advanced pagination only if usage requires it later

Response fields should include:

- `execution_id`
- `status_code`
- `is_success`
- `error_message`
- `dns_lookup_ms`
- `tcp_connection_ms`
- `tls_handshake_ms`
- `ttfb_ms`
- `total_latency_ms`
- `response_size_bytes`
- `redirect_count`
- `checked_at`

## 7. Database Schema Design

The schema should support both the current product behavior and the worker-state bookkeeping needed for Stage 3.

### 7.1. `users` Table

Stores authentication data. Passwords must be hashed before insertion.

```sql
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### 7.2. `endpoints` Table

This table stores both endpoint configuration and the current scheduler state.

```sql
CREATE TABLE endpoints (
    id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                   VARCHAR(255) NOT NULL,
    url                    TEXT NOT NULL,
    method                 VARCHAR(10) NOT NULL DEFAULT 'GET',
    headers                JSONB,
    body                   TEXT,

    is_active              BOOLEAN NOT NULL DEFAULT TRUE,
    check_interval_minutes INTEGER NOT NULL DEFAULT 5,
    next_check_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    locked_at              TIMESTAMP WITH TIME ZONE,

    consecutive_failures   INTEGER NOT NULL DEFAULT 0,
    failing_since          TIMESTAMP WITH TIME ZONE,
    last_checked_at        TIMESTAMP WITH TIME ZONE,
    last_success_at        TIMESTAMP WITH TIME ZONE,
    last_status_code       INTEGER,
    last_error_message     TEXT,
    last_total_latency_ms  INTEGER,

    created_at             TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT endpoints_method_check
        CHECK (method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE')),
    CONSTRAINT endpoints_interval_check
        CHECK (check_interval_minutes BETWEEN 1 AND 1440),
    CONSTRAINT endpoints_header_shape_check
        CHECK (headers IS NULL OR jsonb_typeof(headers) = 'object'),
    CONSTRAINT endpoints_consecutive_failures_check
        CHECK (consecutive_failures >= 0)
);

CREATE INDEX idx_endpoints_scheduler
ON endpoints(next_check_at, locked_at)
WHERE is_active = TRUE;

CREATE INDEX idx_endpoints_user_id
ON endpoints(user_id, created_at DESC);
```

Why the additional state fields matter:

- they make failure streak logic cheap
- they make list views cheap
- they keep worker behavior deterministic

### 7.3. `test_results` Table

This is the write-heavy history table.

```sql
CREATE TABLE test_results (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    execution_id        UUID UNIQUE NOT NULL,
    endpoint_id         UUID NOT NULL REFERENCES endpoints(id) ON DELETE CASCADE,

    status_code         INTEGER,
    is_success          BOOLEAN NOT NULL,
    error_message       TEXT,

    dns_lookup_ms       INTEGER,
    tcp_connection_ms   INTEGER,
    tls_handshake_ms    INTEGER,
    ttfb_ms             INTEGER,
    total_latency_ms    INTEGER NOT NULL,

    response_size_bytes INTEGER,
    redirect_count      INTEGER NOT NULL DEFAULT 0,

    checked_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_test_results_history
ON test_results(endpoint_id, checked_at DESC);

CREATE INDEX idx_test_results_retention
ON test_results(checked_at);
```

### 7.4. Query Responsibilities by Package

Keep the SQL grouped by behavior, not randomly by table.

Typical repository responsibilities:

- auth queries
  - create user
  - get user by email
- endpoint queries
  - create endpoint
  - list endpoints by user
  - get endpoint by ID and user
  - claim due endpoints
  - complete endpoint check
- result queries
  - insert test result
  - list endpoint history
  - prune old rows

## 8. Development Notes & Common Pitfalls

These are the mistakes most likely to slow the project down or create unstable behavior.

- **Do not let handlers call SQL directly.**
  Once that happens, validation, auth, and business rules become inconsistent.
- **Do not let the pinger know about persistence.**
  It must remain reusable and testable in isolation.
- **Do not keep row locks open during network I/O.**
  That is the easiest way to create lock contention and duplicate scheduling bugs.
- **Do not compute current endpoint state from full history on every list request.**
  Store summary fields on `endpoints`.
- **Do not rely on in-memory timers for correctness across instances.**
  Postgres row locking is the source of truth for job ownership.
- **Do not skip retention.**
  A monitoring system without a pruning strategy eventually becomes a database maintenance problem.

## 9. Final Implementation Checklist

Use this as the high-level completion checklist for the first full version:

1. Boot Postgres locally with one command.
2. Run migrations and generate typed queries.
3. Start the API with typed config, logs, health, and metrics.
4. Implement registration, login, and JWT auth middleware.
5. Implement endpoint creation with validation, quotas, and ownership checks.
6. Implement endpoint listing and result history reads.
7. Implement the pinger with timeout and `httptrace` timing capture.
8. Implement scheduler claim logic using `FOR UPDATE SKIP LOCKED`.
9. Implement worker execution, result inserts, summary-field updates, and lock clearing.
10. Implement backoff, stale-lock recovery, and 24-hour auto-disable behavior.
11. Implement raw-history pruning in batches.

If you build in this order and do not skip the exit criteria between stages, the project stays understandable and each part has a clear reason for existing.
