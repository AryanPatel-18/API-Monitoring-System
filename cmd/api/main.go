package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/AryanPatel-18/API-Monitoring-System/internal/config"
	"github.com/AryanPatel-18/API-Monitoring-System/internal/database"
	repo "github.com/AryanPatel-18/API-Monitoring-System/internal/repository"
)

func main() {
	cfg := config.Load()

	pool, err := database.NewPool(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("failed to connect to DB: %v", err)
	}
	defer pool.Close()

	queries := repo.New(pool)

	// Temporary test insert (remove later)
	user, err := queries.CreateUser(context.Background(), repo.CreateUserParams{
		Email:        "test@example.com",
		PasswordHash: "dummy",
	})
	if err != nil {
		log.Println("query error:", err)
	} else {
		log.Println("user created:", user.ID)
	}

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		err := pool.Ping(ctx)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte("db not ready"))
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	server := &http.Server{
		Addr: ":" + cfg.Port,
	}

	go func() {
		log.Println("server running on port", cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	stop := make(chan struct{})

	go func() {
		c := make(chan os.Signal, 1)
		signal.Notify(c, syscall.SIGINT, syscall.SIGTERM)
		<-c

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		server.Shutdown(ctx)
		close(stop)
	}()

	<-stop
}