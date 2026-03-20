# scripts/

Relayer and agent tooling.

Settlement relayer script that:
1. Monitors destination parachain for XCM execution confirmation
2. Signs settlement proof
3. Calls `ConduitRouter.settle(receiptId, proof)` on Paseo Asset Hub

## Relayer Usage

The relayer automatically loads environment values from:

- exported shell variables
- `.env.local` / `.env` in the current working directory
- `.env.local` / `.env` in this `scripts/` folder
- `.env.local` / `.env` in the repo root

Run from repo root:

```bash
npx tsx scripts/relayer.ts monitor
npx tsx scripts/relayer.ts settle 1
npx tsx scripts/relayer.ts status 1
```

Run from `scripts/`:

```bash
npm run relayer -- monitor
npm run relayer -- settle 1
npm run relayer -- status 1
```

