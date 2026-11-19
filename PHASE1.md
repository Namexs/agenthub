# AGENTHUB — PHASE 1: REPOSITORY FOUNDATION

User order 2026-11-19 ~12:25 WIB. STOP after Phase 1. Wait for approval before Phase 2.

## 1. Initialize the project

Monorepo: pnpm workspaces, Next.js, TypeScript, Tailwind CSS, Foundry, Solidity,
OpenZeppelin Contracts.

```
mkdir agenthub
cd agenthub
pnpm init
mkdir -p apps/web packages/contracts packages/shared packages/config docs .github/workflows
git init
```

Structure: apps/web/, packages/contracts/, packages/shared/, packages/config/,
docs/, .github/workflows/

## 2. Configure development tools

- TypeScript strict mode
- ESLint
- Prettier
- Foundry
- Automated GitHub Actions
- Environment variable validation
- Secure dependency management
- Pin stable dependency versions

## 3. Smart contract preparation (interfaces + architecture only in Phase 1)

AgentGate: verify Agent ID ownership; official Agent ID contract address;
check balanceOf(address); validate expected chain.

QuestManager: create quests, join quests, record completion, prevent duplicate
completion, support cooldowns.

Reputation: record validated reputation events, prevent unauthorized score
manipulation, maintain transparent event history.

Achievement: issue non-transferable achievement records, prevent unauthorized
issuance, support public verification.

Do NOT implement arbitrary administrative score increases.

## 4. Development environments

- LOCAL/TESTNET: mock Agent ID contract for isolated development and testing.
- PRODUCTION: official Agent ID contract 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F.
  Do NOT assume the official mainnet Agent ID contract is deployed on testnet.

## 5. Documentation

README.md, ARCHITECTURE.md, SECURITY.md, DEPLOYMENT.md, USER_GUIDE.md.
Explain architecture and trust assumptions.

## 6. Security

No private key storage, no seed phrase collection, no session impersonation,
no hidden transactions, no insecure env var exposure, no hardcoded deployment secrets.

## 7. Deliverables (Phase 1)

1. Complete directory tree
2. Installation commands
3. Dependency list
4. Environment configuration
5. Architecture explanation
6. Security assumptions
7. Build and test results
8. Any unresolved issues

Run installation, build, lint, and initial test commands.
Never claim a test passed unless it was actually executed.

STOP after Phase 1. Wait for approval before implementing Phase 2.
