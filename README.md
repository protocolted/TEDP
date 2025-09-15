# TEDP

TEDP's smartcontract v3

## Contract

- File: `contracts/TEDPTokenFinalV3.sol`
- Name: `TEDPTokenFinalV3`
- Symbol: `TEDP`
- Decimals: 18
- Version: 3.0.0
- Total supply: 1,000,000,000 TEDP (1e9)
- Deployed address (TRON): `TWd6ewg3Cj9qzZ9Sa5YQ5GryfLvk3JJEKi`

## On-chain References (TRONSCAN)

- Token details: https://tronscan.org/#/token20/TWd6ewg3Cj9qzZ9Sa5YQ5GryfLvk3JJEKi
- Holders: https://tronscan.org/#/token20/TWd6ewg3Cj9qzZ9Sa5YQ5GryfLvk3JJEKi/holders
- Contract code: https://tronscan.org/#/token20/TWd6ewg3Cj9qzZ9Sa5YQ5GryfLvk3JJEKi/code

## Key Features

- Trading enabled at launch
- 0% initial fees (burn, liquidity, staking, treasury)
- Blacklist and permanent blacklist with reason
- Emergency pause, bot protection (optional), cooldown controls
- Exemptions for fees/limits, exchange and LP registration
- Auto-liquidity hooks (placeholder)
- Liquidity lock, TRX and token recovery helpers

## Admin Controls

- Update fees with caps (total ≤ 5%)
- Set max/min transfer and wallet limits
- Toggle fees, anti-bot, auto-liquidity
- Set router and create DEX pair (SunSwap V2 compatible)

## Build & Verify

```bash
# Example (adapt as needed)
# forge build
# or
# tronbox compile
```

## Security Notes

- Production-intended version as of 2025-01-14
- Protect owner keys; consider multisig for sensitive operations
- Always test on testnet before mainnet deployment

## License

MIT
