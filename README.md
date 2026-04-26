# Scheduled HTTP Health Monitoring Service

An API-first backend service built in Go for monitoring the health and latency of public HTTP endpoints. Authenticated users can register endpoints, define check intervals, and retrieve historical health and latency data.

This system is designed for reliable scheduled execution, operational clarity, and high-throughput write performance, ensuring safe and duplicate-free processing across multiple application instances.

## 🌟 Key Features

- **User Authentication**: Secure JWT-based authentication for registering and managing endpoints.
- **Scheduled Monitoring**: Automated health checks for registered HTTP endpoints at user-defined intervals (1 to 1440 minutes).
- **Comprehensive Metrics**: Captures and stores detailed network timings (DNS, TCP, TLS, TTFB, Total Latency) and HTTP status codes for every check.
- **Distributed Worker Pool**: Safe scheduling with PostgreSQL row locking (`FOR UPDATE SKIP LOCKED`) ensures endpoints are checked exactly once per interval, even with multiple app instances running.
- **Resilience & Backoff**: Implements smart backoff strategies for failing endpoints and an auto-disable rule for endpoints failing continuously for 24 hours.
- **Data Retention Strategy**: Automated background pruning of old historical data to maintain database performance.
- **Observability Built-in**: Structured JSON logging, OpenTelemetry tracing, and Prometheus metrics.

## 🛠️ Tech Stack

- **Language**: Go (1.21+)
- **Routing**: `go-chi/chi/v5`
- **Database**: PostgreSQL 16
- **Database Driver/ORM**: `jackc/pgx/v5` & `sqlc` (Type-safe SQL generation)
- **Migrations**: `pressly/goose`
- **Validation**: `go-playground/validator/v10`
- **Authentication**: JWT (HMAC-SHA256) & `bcrypt`

## 🏗️ Architecture & Domain Boundaries

The application follows a modular monolith architecture, enforcing strict boundaries:

- **`handler`**: Parses HTTP requests, validates DTOs, and formats responses. Knows nothing about SQL.
- **`services`**: Contains core business rules, orchestration, and authorization checks.
- **`repository`**: Handles SQL data access (via sqlc).
- **`pinger`**: A pure outbound HTTP execution engine that captures detailed request timings.
- **`worker`**: Manages the scheduler loop, worker pool, and data retention jobs independently from the HTTP transport layer.

## 🚀 Getting Started

### Prerequisites

- [Go](https://golang.org/doc/install) (1.21 or later)
- [Docker](https://docs.docker.com/get-docker/) & Docker Compose
- [Make](https://www.gnu.org/software/make/)

### Local Development

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd ApiTester
   ```

2. **Start the database**
   Spin up the PostgreSQL container using Docker Compose:

   ```bash
   make db-up
   ```

3. **Run database migrations**

   ```bash
   make migrate-up
   ```

4. **Generate SQL queries** (if modifying SQL files)

   ```bash
   make sqlc-generate
   ```

5. **Run the application**

   ```bash
   make run
   ```

   The API will start on the default port (8080).

## 📂 Directory Structure

```text
ApiTester/
├── cmd/
│   └── api/                  # Application entry point, dependency wiring
├── internal/
│   ├── api/                  # HTTP transport layer (handlers & routes)
│   ├── auth/                 # JWT creation and password hashing
│   ├── config/               # Environment loading
│   ├── database/             # Postgres pool initialization
│   ├── middleware/           # Auth, rate limiting, logging, metrics
│   ├── models/               # Domain entities and transport DTOs
│   ├── pinger/               # Outbound HTTP execution and timing capture
│   ├── repository/           # SQL access layer (sqlc-generated)
│   ├── services/             # Business logic and rules
│   └── worker/               # Scheduler loop and worker pool
├── migrations/               # Goose SQL migrations
├── scripts/                  # Development helpers
├── deployments/              # docker-compose.yml
└── docs/                     # Documentation and notes
```

## 📜 Implementation Roadmap

The development of this service is phased to ensure a solid foundation:

1. **Stage 1**: Infrastructure, Tooling & Observability
2. **Stage 2**: Synchronous Services & Clean Abstractions
3. **Stage 3**: Concurrency & the Distributed Worker Pool
4. **Stage 4**: Data Lifecycle & Retention
