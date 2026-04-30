# 🏦 Secure Crowd Fundinng Protocol (Foundry Edition)

A **production-oriented crowdfunding smart contract** built with [Foundry](https://book.getfoundry.sh/), designed to handle **real-world fund flows securely**.

This project goes beyond basics — it demonstrates:
- Secure ETH handling 🔐  
- Deterministic state machine design ⚙️  
- Fee-based economic modeling 💰  
- Audit-aware development mindset 🛡️  

---

# 📚 Table of Contents

- [💼 Why This Project Stands Out](#-why-this-project-stands-out)
- [📁 Project Structure](#-project-structure)
- [⚙️ Getting Started](#️-getting-started)
  - [Requirements](#requirements)
  - [Clone & Build](#clone--build)
- [🚀 Deploying Contracts](#-deploying-contracts)
  - [🧪 Local Deployment](#-local-deployment)
  - [🌐 Testnet Deployment (Sepolia)](#-testnet-deployment-sepolia)
- [🧪 Running Tests](#-running-tests)
- [🧠 Core Contract Logic](#-core-contract-logic)
  - [🔄 State Machine](#-state-machine)
  - [💰 Fee Model](#-fee-model)
  - [🔐 Security Considerations](#-security-considerations)
- [🔗 Chainlink Integration](#-chainlink-integration)
- [📜 Example Interactions](#-example-interactions)
- [🧪 Testing Philosophy](#-testing-philosophy)
- [🛡️ Audit Awareness](#️-audit-awareness)
- [🧠 Concepts Covered](#-concepts-covered)
- [🔍 Upcoming Enhancements](#-upcoming-enhancements)
- [🎯 What This Project Proves](#-what-this-project-proves)
- [🧑‍💻 About](#-about)
- [📌 Notes](#-notes)
- [🧠 License](#-license)
- [⭐ Support](#-support)
- [🙏 Acknowledgment](#-acknowledgment)

---

## 💼 Why This Project Stands Out

Most crowdfunding contracts stop at “fund & withdraw”.

This one implements:

- ✅ **State-driven lifecycle (ACTIVE → SUCCESS → FAILED)**  
- ✅ **User refunds with fee logic**  
- ✅ **Owner withdrawals with platform fees**  
- ✅ **Chainlink price feeds (USD-based funding)**  
- ✅ **Reentrancy protection & CEI pattern**  

👉 Built like a **real DeFi primitive**, not a tutorial.

---

## 📁 Project Structure

```
├── src/              # Core smart contracts
├── script/           # Deployment & interaction scripts
├── test/             # Unit & edge-case tests
├── lib/              # External dependencies
└── foundry.toml      # Foundry configuration
```

---

## ⚙️ Getting Started

### Requirements

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js & NPM](https://nodejs.org/)
- Optional: [Docker](https://docs.docker.com/get-docker/)

---

### Clone & Build

```bash
git clone https://github.com/barnabasmunuhe/Secure-Crowd_Funding-Protocol
cd fund-me
forge install
forge build
```

---

# 🚀 Deploying Contracts

## 🧪 Local Deployment

```bash
forge script script/DeployFundMe.s.sol \
  --fork-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key <PRIVATE_KEY>
```

---

## 🌐 Testnet Deployment (Sepolia)

```bash
forge script script/DeployFundMe.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

---

# 🧪 Running Tests

## Unit Tests

```bash
forge test -vvv
```

## Forked Tests

```bash
forge test --fork-url $SEPOLIA_RPC_URL
```

## Coverage Report

```bash
forge coverage
```

---

# 🧠 Core Contract Logic

## 🔄 State Machine

```
ACTIVE → SUCCESS → FAILED
```

- **ACTIVE** → users can fund  
- **SUCCESS** → owner can withdraw  
- **FAILED** → users can refund  

👉 Ensures predictable and secure behavior.

---

## 💰 Fee Model

- Platform Fee → applied on withdrawals  
- Refund Fee → applied on user refunds  

✔ Implemented using **basis points (BPS)**  
✔ Eliminates floating-point precision errors  

---

## 🔐 Security Considerations

- Reentrancy protection (`ReentrancyGuard`)  
- Access control (`Ownable`)  
- Checks → Effects → Interactions (CEI)  
- Pull-based refund pattern  
- No gas-heavy loops  

---

# 🔗 Chainlink Integration

Uses Chainlink Price Feeds to:

- Convert ETH → USD  
- Enforce minimum contribution threshold  
- Stabilize funding logic  

---

# 📜 Example Interactions

## Fund Contract

```bash
cast send <FUNDME_ADDRESS> "fund()" \
  --value 0.1ether \
  --private-key <PRIVATE_KEY>
```

---

## Withdraw (Owner Only)

```bash
cast send <FUNDME_ADDRESS> "ownerWithdraw(uint256)" \
  --private-key <PRIVATE_KEY>
```

---

## Refund (User)

```bash
cast send <FUNDME_ADDRESS> "refund()" \
  --private-key <PRIVATE_KEY>
```

---

# 🧪 Testing Philosophy

This project focuses on **behavior-driven testing**, including:

- Funding validation  
- Refund correctness (with fee deduction)  
- Owner withdrawal accounting  
- State transitions  
- Edge cases (double refund, insufficient balance, etc.)  

👉 Emphasis on **financial correctness**, not just coverage.

---

# 🛡️ Audit Awareness

During development, a **critical bug** was identified and resolved:

- Incorrect refund transfer logic  
- Could lead to fund imbalance  

✔ Fixed with correct payout calculation  

👉 Demonstrates **audit-level thinking and debugging discipline**

---

# 🧠 Concepts Covered

- Fallback & receive functions  
- msg.value / msg.sender  
- Chainlink oracles  
- Access control patterns  
- Fee modeling (BPS)  
- Smart contract testing (Foundry)  
- Deployment scripting  
- Gas analysis (`forge snapshot`)  

---

# 🔍 Upcoming Enhancements

- Campaign factory (multi-project deployment)  
- DAO-controlled treasury  
- ERC20 funding support  
- Milestone-based payouts  
- Emergency pause mechanism  

---

# 🎯 What This Project Proves

This project demonstrates:

- Real-world **smart contract architecture**  
- Secure **financial logic implementation**  
- Strong **testing discipline**  
- Awareness of **production risks**  

👉 Ready for **DeFi / Smart Contract Engineering roles**

---

# 🧑‍💻 About

Blockchain developer focused on:

- Smart contract engineering  
- Protocol design  
- Security & testing  

---

# 📌 Notes

This is an evolving project focused on **building production-grade Solidity systems**.

Feedback, issues, and PRs are welcome.

---

# 🧠 License

MIT License

---

# ⭐ Support

If you find this useful, consider starring ⭐ the repo.

---

# 🙏 Acknowledgment

Built with focus, discipline, and a deep commitment to mastering smart contract engineering.
