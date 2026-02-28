# cloudflare-terraform

Terraform project managing Cloudflare DNS, Zero Trust Tunnels, and Email Routing for the `jabbson.xyz` domain.

- **Cloudflare provider**: v5 (`~> 5`)
- **Terraform**: >= 1.5.0

## Setup

### 1. Credentials

Copy `.env.example` to `.env` and fill in the three required values:

```bash
cp .env.example .env
# edit .env with your values
source .env
```

| Variable | Description |
|----------|-------------|
| `CLOUDFLARE_API_TOKEN` | Bearer token — the only env var read by the Cloudflare provider |
| `ZONE_ID` | Cloudflare zone ID for the domain |
| `ACCOUNT_ID` | Cloudflare account ID |

### 2. Extra resource files

Copy the `.example` files for any resource types you want to manage via Terraform directly:

```bash
cp dns_extra.auto.tfvars.json.example dns_extra.auto.tfvars.json
cp tunnels_extra.auto.tfvars.json.example tunnels_extra.auto.tfvars.json
cp email_routing_extra.auto.tfvars.json.example email_routing_extra.auto.tfvars.json
```

These files are gitignored. Leave them as empty maps `{}` if you have nothing to add.

### 3. Traefik IP

Copy `traefik.auto.tfvars.example` to `traefik.auto.tfvars` and set your Traefik host IP:

```bash
cp traefik.auto.tfvars.example traefik.auto.tfvars
# edit traefik.auto.tfvars with the real IP
```

This file is gitignored. Update it whenever the Traefik host IP changes.

## Workflow

```bash
# Load credentials
source .env

# Sync live Cloudflare state → regenerate tfvars + imports
./generate.sh

# Standard Terraform (init only needed once or after provider changes)
terraform init
terraform plan
terraform apply
```

### Reset state

Use this after major refactors or to re-import everything clean:

```bash
rm -f terraform.tfstate terraform.tfstate.backup
source .env && ./generate.sh
terraform apply
```

## How it works

`generate.sh` calls the Cloudflare API and writes the following **generated artifacts** (do not edit by hand):

| File | Contents |
|------|----------|
| `dns.auto.tfvars.json` | All DNS records (excluding any in `dns_extra.auto.tfvars.json`) |
| `tunnels.auto.tfvars.json` | Zero Trust tunnels (excluding any in `tunnels_extra.auto.tfvars.json`) |
| `email_routing.auto.tfvars.json` | Email routing rules, addresses, catch-all (excluding any in `email_routing_extra.auto.tfvars.json`) |
| `imports.tf` | Import blocks for every resource (same exclusions apply) |

### Adding resources without generate.sh

Each resource type has a hand-managed "extra" pool for Terraform-native creation. Edit the relevant file and run `terraform plan` → `terraform apply` — no dashboard, no API call, no `generate.sh` needed.

| What to add | File to edit | Template |
|-------------|-------------|----------|
| DNS records | `dns_extra.auto.tfvars.json` | `dns_extra.auto.tfvars.json.example` |
| Tunnels | `tunnels_extra.auto.tfvars.json` | `tunnels_extra.auto.tfvars.json.example` |
| Email addresses + rules | `email_routing_extra.auto.tfvars.json` | `email_routing_extra.auto.tfvars.json.example` |

All three files are gitignored — copy from the `.example` template to get started.

## Project structure

| File | Purpose |
|------|---------|
| `providers.tf` | Cloudflare provider configuration |
| `variables.tf` | Input variable declarations |
| `dns.tf` | DNS records — imported pool (`.this`) + hand-managed pool (`.extra`) |
| `tunnels.tf` | Zero Trust tunnels — imported pool (`.this`) + hand-managed pool (`.extra`) |
| `email_routing.tf` | Email routing settings, addresses, rules, catch-all — imported + extra pools |
| `generate.sh` | Fetches live state from Cloudflare API, writes tfvars + imports |
| `*.auto.tfvars.json.example` | Templates for hand-managed extra resource files (committed) |
| `traefik.auto.tfvars` | Sets `traefik_ip` (gitignored — copy from example) |

## Notes

- All resources use `lifecycle { prevent_destroy = true }`. To remove a resource, delete both the resource block and the lifecycle block.
- Resources are imported from Cloudflare rather than created fresh. `imports.tf` is regenerated on every `generate.sh` run.
- A records tagged `comment = "traefik"` have their content overridden with `var.traefik_ip` at plan time.
