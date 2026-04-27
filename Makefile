DB_URL := postgres://postgres:postgres@localhost:5433/api_tester?sslmode=disable

.PHONY: db-up db-down migrate-up migrate-down sqlc-generate run

db-up:
	docker compose -f deployments/docker-compose.yml up -d

db-down:
	docker compose -f deployments/docker-compose.yml down

migrate-up:
	goose -dir migrations postgres "$(DB_URL)" up

migrate-down:
	goose -dir migrations postgres "$(DB_URL)" down

sqlc-generate:
	sqlc generate

run:
	go run cmd/api/main.go

docker-sql:
	docker exec -it api_tester_db psql -U postgres -d api_tester