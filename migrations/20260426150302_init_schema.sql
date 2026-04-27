-- +goose Up
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE endpoints (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                  VARCHAR(255) NOT NULL,
    url                   TEXT NOT NULL,
    method                VARCHAR(10) NOT NULL DEFAULT 'GET',
    headers               JSONB,
    body                  TEXT,
    is_active             BOOLEAN NOT NULL DEFAULT TRUE,
    check_interval_minutes INTEGER NOT NULL DEFAULT 5,
    next_check_at         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    locked_at             TIMESTAMP WITH TIME ZONE,
    consecutive_failures  INTEGER NOT NULL DEFAULT 0,
    failing_since         TIMESTAMP WITH TIME ZONE,
    last_checked_at       TIMESTAMP WITH TIME ZONE,
    last_success_at       TIMESTAMP WITH TIME ZONE,
    last_status_code      INTEGER,
    last_error_message    TEXT,
    last_total_latency_ms INTEGER,
    created_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

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

-- +goose Down
DROP TABLE IF EXISTS test_results;
DROP TABLE IF EXISTS endpoints;
DROP TABLE IF EXISTS users;

DROP EXTENSION IF EXISTS "uuid-ossp";
