# Two-month cost review — incomplete; not an authorization to plan or apply

The user specified an approximately two-month project horizon and a total $100 Azure for Students credit ceiling. Dev runs about 4–6 hours/week; prod about 2 hours/week. Azure resource charges can continue outside those windows. The user selected Web PubSub Free, with the explicit security trade-off that server REST is publicly reachable and Entra-authenticated.

## Public retail reference points

Read-only queries to the [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) on 2026-11-24 returned these `polandcentral` USD consumption meters. These are **illustrative public prices**, not a subscription quote, proof of availability, selected SKUs, verified free-tier eligibility, or a complete estimate. Confirm every line in the subscription's [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) and actual billing.

| Meter | Reference | Example of 60 days continuously allocated |
|---|---:|---:|
| Managed Redis Balanced B0 | $0.0208/hour | $29.95 for one instance |
| PostgreSQL Flexible Server B1MS compute | $0.0199/hour | $28.66 for one server's compute only |
| Standard static public IPv4 | $0.005/hour | $14.40 for two addresses |
| Web PubSub Standard | $1.61/unit/day | $96.60 for one continuously retained unit |
| Web PubSub Free | Free; 20 connections, 20,000 messages/day | Verify subscription quota and usage; no private endpoints |

Those three example continuous Redis/PostgreSQL/public-IP lines total **$73.01**, before NAT Gateway, PostgreSQL storage/backups, Private Endpoints, DNS, ACR, AKS nodes, load balancers, logging, egress and the second environment. This is a warning, not a project quote: it assumes neither discounts nor stop/destroy windows. PostgreSQL compute may have a subscription-specific offer; do not assume it applies. A single paid Web PubSub Standard instance retained for 60 days would consume most of the budget by itself, but actual unit billing is time-based and session-only lifecycles must be costed separately.

## Required inputs and line items

- [ ] Verify remaining credit, offer-specific benefits, current charges, currency and tax; maintain a safety margin.
- [ ] Choose and verify regional availability/quota and actual price for each AKS node SKU, PostgreSQL SKU/storage/backup, Redis SKU/HA, Web PubSub Free instances, Cosmos free tier and aggregate throughput, and ACR.
- [ ] Estimate per-environment billable hours for AKS, PostgreSQL compute, Redis and Web PubSub, including provisioning/deletion time, failed attempts, auto-restarts, and non-session time. Confirm which services can really be stopped and what continues billing.
- [ ] Estimate retained PostgreSQL storage and backups, Blob data/transactions, Cosmos storage/throughput beyond allowance, Key Vault operations, ACS email, NAT Gateway and data processing, load balancers/rules, static IPs, all private endpoints and data processing, private DNS, logs, state storage, and outbound traffic.
- [ ] Include both dev and prod, shared resources once, all session periods over the two-month horizon, and cost while services are retained or stopped. Identify the exact data destroyed by each proposed lifecycle.
- [ ] Compare the complete aggregate to remaining credit with a safety margin. If it does not fit, obtain a design/lifecycle decision; never treat alerts as a spending cap. Check actual spend throughout the project.
