# Shell unit testing with Bats

This repository uses [Bats](https://github.com/bats-core/bats-core) to exercise bash helpers without touching a live cluster. Below is a step‑by‑step guide for installing Bats, running the existing tests, and writing new ones in this repo’s style.

## Install Bats
- macOS (Homebrew): `brew install bats-core`
- Linux (npm): `npm install -g bats`
- Verify: `bats --version`

## Project layout and conventions
- Tests live under `test/` and use the `.bats` extension.
- Shared helpers live in `test/_helpers.bash` (e.g., `source_repo_scripts`, `setup_kubectl_cabundle_stub`).
- Each test `load _helpers` and sources scripts via the helper (e.g., `deploy/helper.sh`, `deploy/datastores.sh`).
- Cluster interactions are stubbed by shadowing `kubectl` (or other commands) early in `PATH` to keep tests isolated.
- Keep tests fast: use small timeouts like `K8S_READINESS_TIMEOUT=10s`.

## Running tests
- Run all tests: `bats test`
- Run a single file: `bats test/wait_for_webhook_cabundle.bats`
- Show timing: `bats -t test`
- Stop on first failure: `bats --stop-on-failure test`

## Writing tests (recipe)
1. Create `test/<name>.bats` and start with the shebang:
   ```bash
   #!/usr/bin/env bats
   ```
2. Load shared helpers and source the scripts under test in `setup()`:
   ```bash
   load _helpers

   setup() {
     source_repo_scripts
     export K8S_READINESS_TIMEOUT=10s
   }
   ```
3. Stub external commands by prepending a shim to `PATH`. Use the shared `setup_kubectl_cabundle_stub` for webhook tests, or craft a simple inline stub for other commands. Example:
   ```bash
   setup() {
     source_repo_scripts
     export K8S_READINESS_TIMEOUT=10s
     setup_kubectl_cabundle_stub "success_after_empty" "my-webhook" "validatingwebhookconfigurations"
   }
   ```
   - Change the stub logic to simulate the scenarios you need (e.g., errors, different outputs).
4. Write tests with the `@test` directive:
   ```bash
   @test "succeeds once caBundle is populated" {
     KUBECTL_MODE="success_after_empty"
     output=$(wait_for_webhook_cabundle "validatingwebhookconfigurations" "my-webhook" 2>&1)
     status=$?

     [ "$status" -eq 0 ]
     [[ $(cat "$KUBECTL_CALLS_FILE") -ge 2 ]]
     [[ "$output" == *"caBundle injection detected"* ]]
   }
   ```
5. Capture output explicitly when you need to assert on it. Bats sets `$output` only when using `run`; if you call functions directly, assign `output=$(...)` and capture `$?`.
6. Prefer deterministic timeouts: export small values so loops terminate quickly during tests.

## Useful Bats tips
- `run <cmd>` captures exit status, stdout, and stderr (in `$status`, `$output`, and `${lines[@]}`).
- Use temporary files under `$BATS_TEST_TMPDIR` for fixtures and logs.
- Keep stubs minimal and predictable; avoid external state.
- If you add new external commands in scripts, mirror them with stubs in tests to keep CI isolated.

## Current example
- `test/wait_for_webhook_cabundle.bats` validates `wait_for_webhook_cabundle`:
  - Uses `setup_kubectl_cabundle_stub` to return an empty caBundle first, then a populated one.
  - Asserts the success path and the timeout path.
  - Tracks call counts via a temp file to prove the wait loop iterates.
- `test/datastores.bats` validates dispatch and readiness logic:
  - Stubs helper functions to record call order.
  - Confirms `check_webhook_and_service` order, datastore readiness branching, and install/uninstall dispatch.

Follow this pattern when adding new shell helpers: source, stub, simulate scenarios, assert status/output, and keep timeouts short so the suite stays fast.***
