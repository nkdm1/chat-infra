# Two-month cost review — incomplete; not an authorization to plan or apply

The user specified an approximately two-month project horizon and a total $100 Azure for Students credit ceiling, **not** two months of continuous resource allocation. Most resources can be destroyed between use windows; if retention is too costly, even showcase data may be destroyed and regenerated. Azure charges can continue outside those windows for anything retained. The user selected Web PubSub Free, with the explicit security trade-off that server REST is publicly reachable and network ACLs are unavailable; Entra authentication is configured for server operations and must be verified. They also selected AKS load-balancer egress instead of a persistent NAT Gateway; verify load-balancer/SNAT pricing and behavior.

## Proposed 24-hour measurement — not yet approved or run

1. Before planning or provisioning, review remaining credit, target subscription, remote-state recovery/access, resource/SKU/region availability and quota. List the proposed trial resources, known hourly and one-time rates, any resources that remain after teardown, and a safety margin. The user prefers measuring a bounded trial over attempting a complete cost forecast; known rates are context, not an accurate total. Review and explicitly approve the scope and each apply; this document is not deployment authorization.
2. Record a baseline timestamp, existing resource inventory, current credit/charges and resource pricing. Set a 24-hour deadline and an earlier stop condition that preserves the credit margin. Alerts are not hard spending caps.
3. If the trial is approved and provisioned, record actual creation and deletion times, usage, scaling and resource changes. At the deadline destroy only explicitly approved trial resources, in reviewed dependency order; confirm that separately managed PaaS, endpoints, IPs, disks and other billable resources were actually removed or consciously retained. Never delete the state backend as part of trial teardown. Check inventory again afterwards.
4. Review cost and usage by resource and meter against the baseline, not just the aggregate credit balance. **A reading immediately after 24 hours may be incomplete:** Azure's cost data can arrive days late. Recheck over subsequent days, including after deletion, and reconcile delayed charges before deciding what to retain or projecting repeated sessions.
5. Before destroying any application data or secrets, record losses and verify a regeneration/restoration path. Prepare ad-hoc demo seed scripts as needed; they have not yet been implemented or tested.

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

### Spain Central — historical references; not selected

Spain Central was provisionally selected, but Azure policy denied ACR creation there. These historical prices are not the rates for the current Belgium/Sweden configuration. Public Retail Prices API observations on 2026-11-24: Linux `Standard_D2s_v4` $0.107/hour; `Standard_D4s_v4` $0.214/hour; Redis Balanced B0 $0.019/hour; PostgreSQL B1MS compute $0.0199/hour; Standard static public IPv4 $0.005/hour. Availability, actual subscription rates, HA/non-HA meter interpretation, quotas and all other meters remain unverified.

For scale only, two D2s_v4 VMs for 64 total hours cost $13.70 compute, excluding disks and all other charges. One retained B0, B1MS compute and two IPs for 60 days total $70.42 before storage, endpoints and other services; this illustrates retention cost, not the intended default lifecycle. These are not a full lifecycle estimate and cannot be added to the Poland Central examples. AKS system-pool requirements and the subscription's 6-vCPU regional / 4-vCPU family quotas conflict with some potential designs; see `docs/TODO.md`. These historical VM and region examples do not authorize deployment.

For the user's shortlisted nodes, observed Linux retail prices per VM-hour were: Poland Central D2als_v7 $0.0972 and D2pls_v6 $0.0742; Spain Central D2als_v7 $0.0944 and D2pls_v6 $0.0694; Sweden Central D2als_v7 $0.086, D2pls_v5 $0.073, D2pls_v6 $0.0662 and B2pls_v2 $0.0344. These are compute-only reference prices, not usable choices by themselves: the D-family quota was zero in those checks, and Microsoft documents B-series as unsupported for system pools. A 24-hour trial can cost more than 24 node-hours because of provisioning, deletion, additional nodes and all non-node resources.

### Belgium Central and Sweden Central — selected configuration

Public retail lookup reported $0.115/hour for one Linux `Standard_D2s_v4` VM in Belgium Central. This is compute only, not a subscription quote or proof that AKS can allocate it. Web PubSub is configured in Sweden Central; its Free-tier eligibility and cross-region egress charges are unverified. Other Belgium/Sweden trial rates still need review, and billing can continue for retained resources after AKS is removed.

## Required inputs and line items

- [ ] Verify remaining credit, offer-specific benefits, current charges, currency and tax; maintain a safety margin.
- [ ] Choose and verify regional availability/quota and actual price for each AKS node SKU, PostgreSQL SKU/storage/backup, dev Redis `Balanced_B0` with HA disabled, Web PubSub Free instances, Cosmos free tier and aggregate throughput, and ACR. The user selected no Redis HA for either environment.
- [ ] Record actual per-resource hours for AKS, PostgreSQL compute, Redis and Web PubSub, including provisioning/deletion time, failed attempts, auto-restarts, and non-session time. Confirm which services can really be stopped and what continues billing.
- [ ] Track retained PostgreSQL storage and backups, Blob data/transactions, Cosmos storage/throughput beyond allowance, Key Vault operations, ACS email, load balancers/rules and data processing, static IPs, all private endpoints and data processing, private DNS, logs, state storage, and outbound traffic.
- [ ] Include both dev and prod, shared resources once, all session periods over the two-month horizon, and cost while services are retained or stopped. Identify the exact data destroyed by each proposed lifecycle.
- [ ] Compare the proposed trial and ongoing lifecycle to remaining credit with a safety margin. Use observed charges to refine the two-month estimate; if it does not fit, destroy or change explicitly selected resources after data-loss review. Never treat alerts as a spending cap. Check actual spend throughout the project, including delayed billing.
