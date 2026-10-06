# Security review: repository-built ACI runner image

## Overall verdict

**Verdict: NEEDS_CHANGES**

**Deployment as-is is not acceptable (confirmed).** The release-blocking gaps are an unsigned scaler webhook with no repository binding, a mutable ACR image reference, and no protected-environment approval for destructive or publishing workflows. Resolve every HIGH finding before deployment; the MEDIUM findings block describing this as a high-security runner pool.

## Findings

### HIGH — Scaler webhook fails open and accepts unrelated repositories

**Confidence: confirmed.**

**Evidence:** `examples/runner-demo/main.tf:8-31` pins `github-runners` commit `916e8d08874cc1df596a5fd391228d56cba865f1` and passes the three GitHub App secret names but not `webhook_secret_secret_name`. At that commit, `modules/runners/variables.tf:66-69` makes the webhook secret optional, `modules/runners/main.tf:323-325` sets `WEBHOOK_SECRET` only when supplied, and `scaler-function/function_app.py:702-706` validates a signature only when the secret is non-empty. The handler records `repository.full_name` at `scaler-function/function_app.py:724-730` but never compares it with `GITHUB_REPO`; lines 714-733 accept any `workflow_job` payload containing `self-hosted`.

**Impact:** An attacker can point a webhook from a repository they control at this Function. GitHub-originated delivery can pass the GitHub CIDR allowlist, then enqueue runner creation without authentication. Repeated events can consume runner quota, create cost, and starve legitimate jobs.

**Remediation:** Make `webhook_secret_secret_name` mandatory and pass it from the consumer. Fail closed when the secret or signature is absent, verify before parsing, require `payload.repository.full_name == GITHUB_REPO`, and require the complete intended label set. Add negative tests for missing/invalid signatures, wrong repositories, and incomplete labels.

### HIGH — ACI executes whichever manifest currently owns `actions-runner:latest`

**Confidence: confirmed.**

**Evidence:** `.github/workflows/deploy-runners.yml:264-269` builds directly to `actions-runner:latest`. The pinned module hard-codes the same tag at `modules/runners/main.tf:56-59`; the scaler reads it at `scaler-function/function_app.py:473` and sends it to ACI at lines 513-527. No step captures or pins the resulting ACR manifest digest.

**Impact:** The infrastructure revision does not identify the executable image. Rebuilds or retags silently change new runners, rollback cannot select known bytes, and an identity able to write that ACR repository can replace code that receives workflow secrets, OIDC access, and managed identity.

**Remediation:** Build an immutable tag such as `actions-runner:${GITHUB_SHA}`, resolve the ACR digest, and configure `RUNNER_IMAGE` as `registry/actions-runner@sha256:...`. Make the image reference a module input, lock deployed manifests against writes/deletion, retain rollback digests, and deploy the scaler only after digest resolution succeeds.

### HIGH — Apply, destroy, and publish lack an independent approval boundary

**Confidence: confirmed.**

**Evidence:** `.github/workflows/deploy-runners.yml:37-47` exposes `apply` and `destroy` through `workflow_dispatch`; jobs at lines 71 and 339 have no `environment` binding. The workflow grants `id-token: write` at lines 49-51 and logs into Azure at lines 102-107 and 350-355. `.github/workflows/publish-lighthouse-arm.yml:4-13` exposes `publish`; its job at line 28 also has no environment binding and receives `id-token: write` at lines 19-21.

**Impact:** A repository actor permitted to dispatch workflows can obtain the federated Azure identity and destroy infrastructure or publish customer artifacts without independent review. Manual dispatch prevents accidental push execution but does not provide separation of duties.

**Remediation:** Bind apply/destroy and publish jobs to protected environments with required reviewers, prevent self-review, and restrict deployment refs. Split plan from write operations, bind Entra federated credentials to protected environment subjects, and use a separately protected environment and identity for destroy.

### MEDIUM — Ubuntu 20.04 and Azure CLI 2.72 are unsupported

**Confidence: confirmed.**

**Evidence:** `runner-image/Dockerfile:3` pins an image whose OCI metadata identifies Ubuntu 20.04. Lines 8-11 pin Azure CLI `2.72.0-1~focal`, and lines 19-23 use the focal feed. Ubuntu 20.04 ended standard security support in May 2025; Microsoft supports Azure CLI on Ubuntu 22.04/24.04 and requires the latest minor CLI release.

**Impact:** Cloud-privileged workflow code runs on an OS without standard security fixes and a CLI release without current monthly security fixes. Digest pinning freezes that exposure until manually updated.

**Remediation:** Rebase on Ubuntu 24.04 or another currently supported platform and install a currently supported Azure CLI from its matching repository. Add scheduled rebuilds and automated lifecycle/digest update checks. References: [Azure CLI support lifecycle](https://learn.microsoft.com/cli/azure/azure-cli-support-lifecycle) and [Ubuntu end-of-standard-support guidance](https://learn.microsoft.com/azure/update-manager/security-awareness-ubuntu-support).

### MEDIUM — Images have no vulnerability, signature, or provenance gate

**Confidence: confirmed.**

**Evidence:** `runner-image/Dockerfile:3` trusts a third-party GHCR image by digest; lines 13-26 fetch a key and resolve package dependencies during the remote build. `.github/workflows/deploy-runners.yml:264-269` ends after `az acr build` with no SBOM, vulnerability threshold, signature, attestation, or pre-deployment verification. A digest proves byte identity, not publisher or build provenance.

**Impact:** A compromised upstream release, vulnerable base package, or compromised build path can become the privileged runner image without a policy decision. No cryptographic evidence ties the ACR manifest to this repository revision and approved build.

**Remediation:** Generate an SBOM and provenance attestation for the ACR digest, scan before deployment, and fail on policy-defined critical/high findings. Sign with Notation using a protected Key Vault key/certificate and verify signature plus provenance before updating the scaler. Prefer rebuilding from a reviewed upstream source revision. References: [ACR signing guidance](https://learn.microsoft.com/azure/container-registry/secure-container-registry#data-protection) and [registry vulnerability scanning](https://learn.microsoft.com/azure/container-registry/secure-container-registry#logging-and-monitoring).

### MEDIUM — Workflow commands run as root

**Confidence: confirmed.**

**Evidence:** `runner-image/Dockerfile:5` sets `USER root` and never switches back. The pinned upstream digest has no OCI `User` and defaults `RUN_AS_ROOT=true`; the ACI environment at pinned `scaler-function/function_app.py:488-497` does not override it.

**Impact:** Compromised workflow code controls the container filesystem, runner installation, process tree, and credentials created during the job. One-job ACI ephemerality limits persistence but does not protect secrets, OIDC tokens, managed-identity tokens, or outputs during execution.

**Remediation:** Set `RUN_AS_ROOT=false` so the upstream entrypoint drops to its `runner` account, or publish a non-root runtime image. Restrict writable paths and validate representative Azure CLI/Terraform workflows as non-root before rollout.

### MEDIUM — OIDC jobs retain an ambient ACI managed identity

**Confidence: confirmed.**

**Evidence:** `.github/workflows/publish-lighthouse-arm.yml:43-47` selects OIDC and disables Terraform MSI, but pinned `scaler-function/function_app.py:507-512` attaches `runner_pull` to every ACI group. Pinned `modules/runners/main.tf:191-195` grants it `AcrPull`, while lines 199-203 grant every configured `runner_workload_roles` entry at subscription scope. `.github/workflows/deploy-runners.yml:288-309` also grants the same principal write access to runner Terraform state.

**Impact:** Any process can query the ACI managed-identity endpoint regardless of `ARM_USE_MSI=false`, bypassing OIDC subject/environment policy for that identity's permissions. If workload roles are configured, every shared-pool job receives them subscription-wide; with defaults, jobs can still pull ACR content and modify runner state.

**Remediation:** Keep the image-pull identity pull-only and do not reuse it for workload or state permissions. Separate MSI and OIDC workloads into pools with distinct identities, replace role-name inputs with resource-scoped assignments, and never grant a shared runner subscription-scoped workload roles. Treat `AcrPull` as ambient if ACI requires the pull identity to remain attached.

### MEDIUM — ACI has unrestricted egress and no private network boundary

**Confidence: confirmed.**

**Evidence:** The pinned module documents its only `subnet_id` for Function App integration at `modules/runners/variables.tf:181-184`. The ACI request in `scaler-function/function_app.py:499-537` has no subnet, DNS, or egress policy. ACR public access defaults on at `modules/runners/main.tf:107-120` and `modules/runners/variables.tf:187-190`.

**Impact:** Compromised workflow code can exfiltrate source, artifacts, OIDC tokens, managed-identity tokens, or Terraform data to arbitrary destinations. Deleting the ephemeral container cannot revoke leaked data.

**Remediation:** Add an ACI delegated-subnet option and route outbound traffic through NAT plus Azure Firewall or an equivalent policy point. Allow only required GitHub, Azure, package, and customer endpoints. Use private endpoints/private DNS for ACR and storage, disable public access after validation, and monitor egress.

### MEDIUM — Security-sensitive Actions use mutable major tags

**Confidence: confirmed.**

**Evidence:** `.github/workflows/deploy-runners.yml:91,102,109,350` uses `actions/checkout@v4`, `azure/login@v2`, and `hashicorp/setup-terraform@v3`. `.github/workflows/publish-lighthouse-arm.yml:52,63,70` uses the same mutable tags in a job with OIDC, secrets, Azure access, and ambient managed identity.

**Impact:** A moved or compromised action tag changes executable code without repository review and can expose GitHub/Azure tokens or alter infrastructure and artifacts.

**Remediation:** Pin each action to a reviewed full commit SHA, retain its version as a comment, and automate SHA update PRs. Enforce an action allowlist/immutable-action policy and review transitive composite actions.

### LOW — The public repository lacks an enforceable trusted-workflow boundary for this pool

**Confidence: likely.** Repository visibility is public and the module contains no runner-group restriction; GitHub settings must be checked for an external policy that could reduce this risk.

**Evidence:** `.github/workflows/publish-lighthouse-arm.yml:32-36` targets generic labels. Pinned `modules/runners/variables.tf:237-241` defaults to `azure,container-instance,self-hosted`, while `scaler-function/function_app.py:718-722` treats `self-hosted` alone as sufficient. The ACI environment at lines 488-497 provides no dedicated `RUNNER_GROUP`. Current self-hosted workflows are manual, but the runner configuration cannot prevent a future pull-request workflow from selecting the pool.

**Impact:** If a workflow later checks out fork or other untrusted code on these labels, it will execute as root with ambient identity and possible OIDC/secrets access. Ephemerality prevents persistence between jobs, not compromise during a job.

**Remediation:** Prefer a private repository. Otherwise use a dedicated restricted runner group with unique purpose labels, prohibit `pull_request` and `pull_request_target` workloads from this pool through policy/review, and keep untrusted PR validation on GitHub-hosted runners with read-only permissions and no secrets. Require approval before trusted jobs consume PR-produced artifacts.
