# Two-month cost review — incomplete; not an authorization to plan or apply

The user specified an approximately two-month project horizon and a total $100 Azure for Students credit ceiling. Dev runs about 4–6 hours/week; prod about 2 hours/week. Azure resource charges can continue outside those windows. The user selected Web PubSub Free, with the explicit security trade-off that server REST is publicly reachable and Entra-authenticated. They also selected AKS load-balancer egress instead of a persistent NAT Gateway; verify load-balancer/SNAT pricing and behavior.

## Public retail reference points

Read-only queries to the [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) on 2026-11-24 returned these `polandcentral` USD consumption meters. These are **illustrative public prices**, not a subscription quote, proof of availability, selected SKUs, verified free-tier eligibility, or a complete estimate. Confirm every line in the subscription's [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) and actual billing.

| Meter | Reference | Example of 60 days continuously allocated |
|---|---:|---:|
| Managed Redis Balanced B0 | $0.0208/hour | $29.95 for one instance; verify actual non-HA pricing |
| PostgreSQL Flexible Server B1MS compute | $0.0199/hour | $28.66 for one server's compute only |
| Standard static public IPv4 | $0.005/hour | $14.40 for two addresses |
| Web PubSub Standard | $1.61/unit/day | $96.60 for one continuously retained unit |
| Web PubSub Free | Free; 20 connections, 20,000 messages/day | Verify subscription quota and usage; no private endpoints |

Those three example continuous Redis/PostgreSQL/public-IP lines total **$73.01**, before PostgreSQL storage/backups, Private Endpoints, DNS, ACR, AKS nodes, load balancers, logging, egress and the second environment. This is a warning, not a project quote: it assumes neither discounts nor stop/destroy windows. PostgreSQL compute may have a subscription-specific offer; do not assume it applies. A single paid Web PubSub Standard instance retained for 60 days would consume most of the budget by itself, but actual unit billing is time-based and session-only lifecycles must be costed separately.

### Spain Central candidate — not yet selected

The user approved *reviewing* Spain Central; the checked-in region remains Poland Central. Public Retail Prices API observations on 2026-11-24: Linux `Standard_D2s_v4` $0.107/hour; `Standard_D4s_v4` $0.214/hour; Redis Balanced B0 $0.019/hour; PostgreSQL B1MS compute $0.0199/hour; Standard static public IPv4 $0.005/hour. Availability, actual subscription rates, HA/non-HA meter interpretation, quotas and all other meters remain unverified.

For scale only, two D2s_v4 VMs for 64 total hours cost $13.70 compute, excluding disks and all other charges. One retained B0, B1MS compute and two IPs for 60 days total $70.42 before storage, endpoints and other services. These are not a full lifecycle estimate and cannot be added to the Poland Central examples. AKS system-pool requirements and the subscription's 6-vCPU regional / 4-vCPU family quotas conflict with some potential designs; see `docs/TODO.md`. No VM, region or deployment is authorized by these estimates.

## Required inputs and line items

- [ ] Verify remaining credit, offer-specific benefits, current charges, currency and tax; maintain a safety margin.
- [ ] Choose and verify regional availability/quota and actual price for each AKS node SKU, PostgreSQL SKU/storage/backup, dev Redis `Balanced_B0` with HA disabled, Web PubSub Free instances, Cosmos free tier and aggregate throughput, and ACR. The user selected no Redis HA for either environment.
- [ ] Estimate per-environment billable hours for AKS, PostgreSQL compute, Redis and Web PubSub, including provisioning/deletion time, failed attempts, auto-restarts, and non-session time. Confirm which services can really be stopped and what continues billing.
- [ ] Estimate retained PostgreSQL storage and backups, Blob data/transactions, Cosmos storage/throughput beyond allowance, Key Vault operations, ACS email, load balancers/rules and data processing, static IPs, all private endpoints and data processing, private DNS, logs, state storage, and outbound traffic.
- [ ] Include both dev and prod, shared resources once, all session periods over the two-month horizon, and cost while services are retained or stopped. Identify the exact data destroyed by each proposed lifecycle.
- [ ] Compare the complete aggregate to remaining credit with a safety margin. If it does not fit, obtain a design/lifecycle decision; never treat alerts as a spending cap. Check actual spend throughout the project.
