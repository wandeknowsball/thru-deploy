# thru-deploy

A resilient deployment helper for [Thru](https://thru.org) blockchain programs.

Built after spending hours fighting RPC timeouts, crashes, and cryptic errors deploying my first program on Thru alphanet. This tool handles all of it automatically so you don't have to.

## What it handles
- RPC timeouts at any step
- Node fully down (connection refused)
- Smart resume — picks up exactly where it left off
- Meta account conflicts — tells you to use a new seed instead of looping forever
- Nonce too low — correctly identifies this as a success, not an error
- Exponential backoff — waits longer between each retry, caps at 120s

## Usage

```bash
chmod +x thru-deploy.sh
./thru-deploy.sh <seed> <path-to-binary>
```

### Example
```bash
./thru-deploy.sh thru_program2 ./build/thruvm/bin/my_program.bin
```

## Configuration (optional)
| Variable | Default | Description |
|---|---|---|
| `THRU_MAX_RETRIES` | 20 | Max retry attempts |
| `THRU_INITIAL_BACKOFF` | 15 | Initial wait in seconds |
| `THRU_MAX_BACKOFF` | 120 | Max wait between retries |
| `THRU_BACKOFF_MULTIPLIER` | 2 | Backoff growth factor |

### Example with custom config
```bash
THRU_MAX_RETRIES=30 THRU_INITIAL_BACKOFF=10 ./thru-deploy.sh thru_program2 ./build/thruvm/bin/my_program.bin
```

## Requirements
- Linux / macOS (or WSL2 on Windows)
- [Thru CLI](https://thru.org) installed (`cargo install thru`)

## Built by
[@wandeknowsball](https://x.com/wandeknowsball) — building on Thru alphanet
