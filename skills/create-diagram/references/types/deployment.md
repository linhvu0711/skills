# Deployment

Answers: where things run and how they reach each other. Hosts, containers, functions, networks, and the artifacts placed on them.

## Facts to collect

- Execution nodes: cloud accounts, regions, VPCs, clusters, VMs, containers, browsers, phones. Read them from infra code, compose files, k8s manifests, Dockerfiles, CI deploy jobs, `Procfile`. `path` to the definition.
- Artifacts deployed on each node: images, bundles, functions, static sites. `path` to the build output definition.
- Managed services: databases, queues, object stores, identity, CDN.
- Network paths: protocol and port, load balancers, ingress rules, private links. Direction is who opens the connection.
- Environment differences only when the question is about them; otherwise draw production.

## Draw it

| Thing | Data |
|---|---|
| Host or runtime | `device`, `sub` with the runtime: `node 22`, `k8s pod`, `lambda` |
| Artifact on a host | `file` node inside a group, or the host's `note` when one artifact per host |
| Managed service | `store` / `queue` / `box` with `tag: "managed"` |
| Container host, cluster, VPC, region | nested group `zone`, `sub` with the identifier |
| Network path | edge, label `https :443`, `grpc`, `postgres :5432`; `dashed` for async or scheduled |
| Client | `device` with `sub: "browser"` or `actor` |

## Layout

Clients on the left. Edge and ingress next. Compute in the middle inside its cluster group. Data services on the right. Nesting shows region, then VPC, then cluster.

## Budget

6 to 16 nodes, 3 nesting levels at most.

## Pitfalls

- Drawing the logical architecture with cloud icons. The nodes are hosts, not modules; a module appears only as an artifact placed on a host.
- Guessing topology from code. When no infra definition exists, say so in `findings` and draw only what the code proves (a `DATABASE_URL`, a queue client).
