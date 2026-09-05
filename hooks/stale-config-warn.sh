#!/bin/sh
# PreToolUse hook on Bash. When a command launches a service with environment
# variables, injects a reminder to read the variable names out of the real config
# source rather than out of .env.example or the README.
#
# WHY. .env.example and README are documentation: they drift silently across
# renames and refactors, and nothing fails when they do. The code that reads the
# variable cannot drift — it either reads it or it doesn't.
#
# Warns, never blocks.

set -e

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

launch_match=""
case "$cmd" in
  *"cargo run"*) launch_match="cargo run" ;;
  *"mvn spring-boot:run"*|*"mvn -DskipTests=true spring-boot:run"*) launch_match="mvn spring-boot:run" ;;
  *"./mvnw spring-boot:run"*) launch_match="mvnw spring-boot:run" ;;
  *"npm start"*|*"npm run start"*|*"npm run dev"*) launch_match="npm start/dev" ;;
  *"yarn start"*|*"yarn dev"*) launch_match="yarn start/dev" ;;
  *"pnpm start"*|*"pnpm dev"*) launch_match="pnpm start/dev" ;;
  *"python -m"*|*"python3 -m"*|*"uvicorn "*|*"fastapi run"*|*"flask run"*) launch_match="python module" ;;
  *"gradle run"*|*"gradle bootRun"*|*"./gradlew run"*|*"./gradlew bootRun"*) launch_match="gradle run" ;;
  *"docker compose up"*|*"docker-compose up"*) launch_match="docker compose up" ;;
  *)
    case "$cmd" in
      *"docker run "*"-e "*) launch_match="docker run" ;;
    esac
    ;;
esac

[ -z "$launch_match" ] && exit 0

# Only when the command actually carries env assignments / -e flags.
case "$cmd" in
  *=*) ;;
  *" -e "*) ;;
  *) exit 0 ;;
esac

ctx=$(printf '[stale-config check] launch detected: %s.\n\nVerify env var names, endpoints and ports against the REAL config source:\n  Rust    -> src/config.rs, src/main.rs (env::var / clap)\n  Java    -> application.yml, application.properties, @Value annotations\n  Python  -> settings.py, pydantic Settings model, os.environ usage\n  Node    -> process.env usage in src/, dotenv config\n\nDo NOT trust .env.example / README / docs — they go stale on every rename.\nenv vars taken from docker-compose.*.yml or a k8s manifest ARE a valid source (live infra).' "$launch_match")

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
