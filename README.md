# PasaTanda Move Smart Contracts

## 📦 Package Information

**Package ID (Testnet):** `0xa48c115fbf1248c9413c3c655b7961bab694a57dd8b3961d4ba54b963c34058a`

**Module:** `pasatanda_core`

**Network:** Sui Testnet

---

## 🏗️ Architecture Overview

PasaTanda is a decentralized ROSCA (Rotating Savings and Credit Association) - known as "Tanda" in Latin America - implemented on Sui blockchain.

### Core Concepts

- **Tanda (Shared Object):** Each ROSCA cycle is a shared object accessible by all participants
- **Turn-based Payouts:** Participants receive the pool in a fixed, immutable order
- **Atomic DeFi Integration:** Designed to integrate with NAVI Protocol for yield generation
- **Relayer Pattern:** Supports backend-sponsored transactions for fiat/cross-chain deposits

---

## 📋 Functions

### `create_tanda<CoinType>`
Creates a new Tanda with specified participants and configuration.

```bash
sui client call --package <PACKAGE_ID> --module pasatanda_core --function create_tanda \
  --type-args 0x2::sui::SUI \
  --args '[<participant1>, <participant2>, ...]' <contribution_amount> <guarantee_amount> '<fiat_vault_option>' 0x6 \
  --gas-budget 50000000
```

### `deposit_guarantee<CoinType>`
Deposit the initial guarantee. All participants must deposit before the tanda becomes active.

```bash
sui client call --package <PACKAGE_ID> --module pasatanda_core --function deposit_guarantee \
  --type-args 0x2::sui::SUI \
  --args <tanda_id> <coin_object_id> 0x6 \
  --gas-budget 20000000
```

### `deposit_payment<CoinType>`
Deposit monthly contribution (sender is beneficiary).

```bash
sui client call --package <PACKAGE_ID> --module pasatanda_core --function deposit_payment \
  --type-args 0x2::sui::SUI \
  --args <tanda_id> <coin_object_id> 0x6 \
  --gas-budget 20000000
```

### `deposit_payment_for<CoinType>`
Deposit on behalf of another participant (Relayer pattern for fiat/cross-chain).

```bash
sui client call --package <PACKAGE_ID> --module pasatanda_core --function deposit_payment_for \
  --type-args 0x2::sui::SUI \
  --args <tanda_id> <coin_object_id> <beneficiary_address> 0x6 \
  --gas-budget 20000000
```

### `payout_round<CoinType>`
Claim the pool for the current round. Only the participant whose turn it is can call this.

```bash
# withdrawal_type: 0 = Crypto (direct), 1 = Fiat (to vault)
sui client call --package <PACKAGE_ID> --module pasatanda_core --function payout_round \
  --type-args 0x2::sui::SUI \
  --args <tanda_id> <withdrawal_type> 0x6 \
  --gas-budget 20000000
```

### `close_tanda<CoinType>`
Close the tanda after all rounds complete, returning guarantees.

```bash
sui client call --package <PACKAGE_ID> --module pasatanda_core --function close_tanda \
  --type-args 0x2::sui::SUI \
  --args <tanda_id> <admin_cap_id> 0x6 \
  --gas-budget 30000000
```

---



## 🔐 Security Features

1. **Immutable Participant Order:** Once created, the turn order cannot be modified
2. **Turn Verification:** Only the correct participant can claim each round
3. **Phase Management:** State transitions are strictly controlled
4. **Admin Capability:** Protected administrative functions
5. **Event Emission:** All important actions emit events for off-chain monitoring

---

## 📡 Events

| Event | Description |
|-------|-------------|
| `TandaCreated` | New tanda initialized |
| `GuaranteeDeposited` | Participant paid guarantee |
| `PaymentDeposited` | Round contribution received |
| `PayoutExecuted` | Pool distributed to winner |
| `FiatWithdrawalRequested` | Fiat payout requested (for backend) |
| `RoundAdvanced` | Round counter incremented |
| `PhaseChanged` | Tanda state transition |
| `TandaClosed` | Tanda finalized |

---

