# ╔══════════════════════════════════════════════════════════════╗
# ║  Echo — Makefile                                             ║
# ╚══════════════════════════════════════════════════════════════╝

.DEFAULT_GOAL := help
.PHONY: help get clean analyze format codegen apk build-ios build-android run-ios run-android \
        db-migrate db-migrate-local db-functions supabase-start supabase-stop \
        test test-coverage

# ── Colors ────────────────────────────────────────────────────────────────────
CYAN  := \033[36m
RESET := \033[0m
BOLD  := \033[1m

# ─────────────────────────────────────────────────────────────────────────────
help: ## Mostra questo messaggio
	@echo ""
	@echo "  $(BOLD)Echo — comandi disponibili$(RESET)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(CYAN)%-22s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# ── Flutter ───────────────────────────────────────────────────────────────────
get: ## Installa le dipendenze (flutter pub get)
	flutter pub get

clean: ## Pulisce build e cache
	flutter clean
	flutter pub get

analyze: ## Analisi statica del codice
	flutter analyze --no-pub

format: ## Formatta tutto il codice Dart
	dart format lib/ test/

codegen: ## Rigenera i file generati (freezed, json_serializable)
	dart run build_runner build --delete-conflicting-outputs

codegen-watch: ## Rigenera in watch mode
	dart run build_runner watch --delete-conflicting-outputs

# ── Run ───────────────────────────────────────────────────────────────────────
run-ios: ## Avvia l'app su simulatore iOS
	flutter run -d iPhone

run-android: ## Avvia l'app su emulatore Android
	flutter run -d emulator

run: ## Avvia l'app sul primo device disponibile
	flutter run

# ── Build ─────────────────────────────────────────────────────────────────────
build-ios: ## Build IPA (release) per iOS
	flutter build ipa --release

apk: build-android ## Alias rapido per build-android

build-android: ## Build APK (release) per Android
	flutter build apk --release

build-appbundle: ## Build App Bundle per Play Store
	flutter build appbundle --release

# ── Test ──────────────────────────────────────────────────────────────────────
test: ## Esegue tutti i test
	flutter test

test-coverage: ## Test con report di copertura (apre lcov se disponibile)
	flutter test --coverage
	@which genhtml > /dev/null 2>&1 && genhtml coverage/lcov.info -o coverage/html && open coverage/html/index.html || echo "  Installa lcov per il report HTML"

# ── Supabase ──────────────────────────────────────────────────────────────────
supabase-start: ## Avvia Supabase in locale (Docker)
	supabase start

supabase-stop: ## Ferma Supabase locale
	supabase stop

supabase-status: ## Stato del progetto Supabase locale
	supabase status

db-migrate: ## Applica tutte le migration sul progetto remoto
	@echo "  Applica le migration in ordine su Supabase remoto..."
	@for f in supabase/migrations/*.sql; do \
		echo "  → $$f"; \
		supabase db push; \
		break; \
	done

db-migrate-local: ## Applica le migration sul DB locale
	supabase db reset

db-diff: ## Genera una nuova migration dal diff con il DB locale
	@read -p "  Nome migration (es. add_feature): " name; \
	supabase db diff --use-migra -f "$$name"

db-functions: ## Deploy delle Edge Functions su Supabase remoto
	supabase functions deploy ai-echo

# ── Utilità ───────────────────────────────────────────────────────────────────
upgrade: ## Aggiorna tutte le dipendenze Flutter
	flutter pub upgrade

doctor: ## Controlla l'ambiente Flutter
	flutter doctor -v

icons: ## Rigenera le icone dell'app (richiede flutter_launcher_icons)
	dart run flutter_launcher_icons

splash: ## Rigenera lo splash screen (richiede flutter_native_splash)
	dart run flutter_native_splash:create

open-ios: ## Apre il progetto iOS in Xcode
	open ios/Runner.xcworkspace

open-android: ## Apre il progetto Android in Android Studio
	open -a "Android Studio" android
