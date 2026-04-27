# Implementation Tasklist

This tasklist follows the phased delivery strategy outlined in the project plan.

## Stage 1: Infrastructure, Tooling & Observability

**Goal:** Establish a strict, debuggable foundation before writing business logic.

- [x] **1.1. Containerized Development Environment**
  - [ ] Create `deployments/docker-compose.yml` for PostgreSQL 16.
  - [ ] Set up named Docker volume for data persistence.
- [ ] **1.2. Make Targets**
  - [ ] Create `Makefile` with targets: `db-up`, `db-down`, `migrate-up`, `migrate-down`, `sqlc-generate`, `run`.
- [ ] **1.3. Configuration Contract**
  - [ ] Implement central environment loading in `internal/config` (`PORT`, `DATABASE_URL`, `JWT_SECRET`).
  - [ ] Ensure fail-fast startup behavior on missing/malformed config.
- [ ] **1.4. Database Bootstrap and Migrations**
  - [ ] Initialize Goose migrations in `migrations/`.
  - [ ] Add migration to enable `uuid-ossp` extension.
  - [ ] Create base tables (`users`, `endpoints`, `test_results`) and indexes.
  - [ ] Add `sqlc` configuration.
  - [ ] Generate basic typed queries (create user, get user, create endpoint, etc.).
- [ ] **1.5. Application Bootstrap**
  - [ ] Wire application in `cmd/api/main.go`.
  - [ ] Initialize `slog` logger.
  - [ ] Open Postgres connection pool.
  - [ ] Build Chi router.
  - [ ] Register `/health` and `/metrics` routes.
  - [ ] Install request ID and logging middleware.
  - [ ] Implement graceful shutdown.
- [ ] **1.6. Rate Limiting (Optional)**
  - [ ] Add lightweight in-process rate limiting on auth routes (per-IP limits).

## Stage 2: Synchronous Services & Clean Abstractions

**Goal:** Build the synchronous user flows and the core domain rules before introducing background execution.

- [ ] **2.1. Domain Models and DTOs**
  - [ ] Define transport DTOs (`RegisterRequest`, `LoginRequest`, `CreateEndpointRequest`, etc.).
  - [ ] Define domain entities (`User`, `Endpoint`, `TestResult`).
- [ ] **2.2. Authentication Flow**
  - [ ] Implement `POST /v1/auth/register` (password hashing, user insertion).
  - [ ] Implement `POST /v1/auth/login` (password verification, JWT issuance).
  - [ ] Implement JWT authentication middleware.
- [ ] **2.3. Repository Interfaces**
  - [ ] Define interfaces for user store, endpoint store, and result store to allow mocking in services.
- [ ] **2.4. The Pinger Abstraction (`internal/pinger`)**
  - [ ] Implement pure HTTP execution logic.
  - [ ] Capture detailed network timings using `httptrace`.
  - [ ] Implement timeout and error handling.
- [ ] **2.5. Endpoint Service Rules**
  - [ ] Enforce validation constraints (URL schemes, max headers, body size).
  - [ ] Set default values (method, interval) and quotas (10 active endpoints per user).
  - [ ] Enforce ownership rules (users only access their endpoints).
- [ ] **2.6. API Handlers & Error Mapping**
  - [ ] Implement standard JSON error envelope (`{"error": {"code": "...", "message": "..."}}`).
  - [ ] Implement `POST /v1/endpoints` to register an endpoint.
- [ ] **2.7. Read Paths**
  - [ ] Implement `GET /v1/endpoints` to list authenticated user's endpoints.
  - [ ] Implement `GET /v1/endpoints/{id}/results` to fetch recent results for one endpoint.

## Stage 3: Concurrency & the Distributed Worker Pool

**Goal:** Move scheduled checks out of synchronous request flow and into a crash-tolerant background system.

- [ ] **3.1. Scheduler Design**
  - [ ] Implement background goroutine for the scheduler loop.
  - [ ] Write the safe claiming Postgres query (`FOR UPDATE SKIP LOCKED`).
- [ ] **3.2. Dispatch Pipeline**
  - [ ] Implement buffered job channel for claimed endpoints.
  - [ ] Set up fixed worker pool.
  - [ ] Implement global semaphore to cap concurrent outbound requests.
- [ ] **3.3. Worker Execution Flow**
  - [ ] Generate unique `execution_id` for idempotency.
  - [ ] Execute ping via the `pinger` abstraction.
  - [ ] Insert result into `test_results`.
  - [ ] Update endpoint state (`locked_at`, `last_checked_at`, `consecutive_failures`, etc.).
- [ ] **3.4. Success, Failure, and Rescheduling Rules**
  - [ ] Implement backoff scheduling for consecutive failures (1m, 5m, 15m).
  - [ ] Implement 24-hour auto-disable rule using `failing_since`.

## Stage 4: Data Lifecycle & Retention

**Goal:** Keep the write-heavy history table from growing without bound.

- [ ] **4.1. Retention Policy**
  - [ ] Implement policy to keep raw `test_results` rows for 30 days.
- [ ] **4.2. Pruning Worker**
  - [ ] Implement background goroutine to run pruning periodically.
  - [ ] Implement logic to delete old rows in batches (e.g., 5000 rows) to avoid long locks.
- [ ] **4.3. Query Optimization**
  - [ ] Ensure endpoint history and pruning queries use indexes efficiently without full table scans.
