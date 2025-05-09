# Pectra Batch Operations Smart Contract

## Overview

This repository contains the `Pectra.sol` smart contract, designed to facilitate batch operations for Ethereum validator management tasks introduced in the Pectra (Prague + Electra) network upgrade. It leverages **EIP-7702 (Set EOA account code)** to allow validator withdrawal Externally Owned Accounts (EOAs) to execute multiple operations (consolidation, credential switching, Execution Layer exits) in a single, atomic transaction.

This overcomes the limitation of the official Ethereum Foundation "system assembly" (`sys-asm`) contracts, which only permit one operation per transaction and require direct initiation by the withdrawal EOA.

The contract is audited by Quantstamp [Audit Report](https://github.com/Luganodes/Pectra-Batch-Contract/blob/main/audits/quantstamp/Audit.pdf)

**Key Benefits:**

* **Efficiency:** Perform actions across many validators simultaneously.
* **Gas Savings:** Amortize the base transaction fee over multiple operations.
* **Convenience:** Simplify workflows for managing validator fleets.

## Background: Pectra Upgrade & System Contracts

The Pectra upgrade introduces several key EIPs relevant to this project:

* **[EIP-7251: Increase the MAX_EFFECTIVE_BALANCE](https://eips.ethereum.org/EIPS/eip-7251):** Increases the max validator balance to 2048 ETH, enabling auto-compounding (with `0x02` credentials) and consolidation.
* **[EIP-7002: Execution Layer Triggerable Exits](https://eips.ethereum.org/EIPS/eip-7002):** Allows initiating validator exits (full/partial) via transactions from the withdrawal EOA.
* **[EIP-7702: Set EOA account code for one transaction](https://eips.ethereum.org/EIPS/eip-7702):** Allows an EOA to temporarily execute code as if it were a smart contract, enabling this batching pattern.

The official `sys-asm` contracts provide the low-level interface for these operations but lack batching capabilities:
* Consolidation/Switching Target: `0x0000BBdDc7CE488642fb579F8B00f3a590007251`
* EL Exit Target: `0x00000961Ef480Eb55e80D19ad83579A64c007002`
    *(**Important:** Always verify these addresses against official Ethereum Foundation sources before mainnet use!)*

## Features

The `Pectra.sol` contract provides the following batch functions:

1.  `batchConsolidation`: Consolidate stake from multiple source validators into one target validator.
2.  `batchSwitch`: Switch withdrawal credentials from `0x01` to `0x02` for multiple validators.
3.  `batchELExit`: Trigger full or partial Execution Layer exits for multiple validators.

## How it Works: Leveraging EIP-7702

The core mechanism relies on EIP-7702:

1.  **Transaction:** The validator's withdrawal EOA signs and sends an EIP-7702 transaction.
2.  **Code Execution:** This transaction specifies the `Pectra.sol` contract's bytecode and the desired batch function call (e.g., `batchConsolidation(...)` with validator pubkeys).
3.  **EOA Emulation:** For the duration of this transaction, the withdrawal EOA *executes* the `Pectra.sol` code. Inside the contract, `msg.sender` and `address(this)` both refer to the withdrawal EOA's address.
4.  **Authorization:** The `onlySelf` modifier (`require(msg.sender == address(this))`) ensures the batch functions can *only* run in this EIP-7702 context.
5.  **Iterative Calls:** The batch function loops through the provided validator data, making individual, low-level `.call()`s to the appropriate official `sys-asm` contract (`consolidationTarget` or `exitTarget`).
6.  **Origin Preservation:** Crucially, these low-level calls originate *from the withdrawal EOA's address*, satisfying the security requirement of the `sys-asm` contracts.

![Flow Diagram](https://i.imgur.com/bLdGa3Q.png)

## Security

> [Audit Report](https://github.com/Luganodes/Pectra-Batch-Contract/blob/main/audits/quantstamp/Audit.pdf)

* **EIP-7702 Authorization:** The primary security relies on the EIP-7702 transaction being signed by the legitimate withdrawal EOA's private key.
* **`onlySelf` Modifier:** Prevents unauthorized calls to the batch functions outside the EIP-7702 context.
* **Input Validation:** Rigorous checks on input data lengths and formats.
* **Immutable Targets:** The official `sys-asm` contract addresses are hardcoded and immutable, preventing redirection.
* **Stateless:** The batching contract itself holds no state related to the validators.
* **Failure Handling:** Individual operation failures within a batch emit events and allow the rest of the batch to continue (the transaction doesn't revert unless there's a batch-level configuration error).

## Usage

### Primary Method: EIP-7702 via CLI

The intended way to use this contract is via EIP-7702 transactions, typically constructed and sent using a helper tool.

**Recommended Tool: `pectra-cli`**

A dedicated CLI tool simplifies the process of creating and sending these batch transactions:
[https://github.com/Luganodes/pectra-cli](https://github.com/Luganodes/pectra-cli)

Please refer to the `pectra-cli` repository for installation and usage instructions.

### Local Development & Testing (Foundry)

You can compile and test the contract locally using Foundry.

**Prerequisites:**

* [Foundry](https://book.getfoundry.sh/getting-started/installation) (Forge & Cast) installed.
* Git

**Setup:**

```bash
git clone <this_repository_url>
cd <repository_directory>
# Install dependencies if specified (e.g., forge-std)
# forge install
```

**Compile:**

```bash
forge build
```

**Run Tests:**

The test suite (`test/Pectra.t.sol`) uses Foundry cheatcodes (`vm.prank`, `vm.etch`, `vm.expectEmit`, etc.) to simulate the EIP-7702 execution environment and test various scenarios, including edge cases and failures.

```bash
forge test
```

**Deployment (Optional - Not Primary Usage):**

While the main usage pattern is ephemeral execution via EIP-7702, you can deploy the contract persistently using Foundry if needed (e.g., for reference or specific testing scenarios).

```bash
# Ensure RPC_URL and PRIVATE_KEY are set in your environment or use flags
# Example: export RPC_URL=... ; export PRIVATE_KEY=...
forge create src/Pectra.sol:Pectra --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```
**Note:** Remember that calling functions on a *deployed* `Pectra` contract directly from a standard EOA will fail the `onlySelf` modifier check. Interaction still requires an EIP-7702 transaction where the withdrawal EOA emulates this contract's code.

## Contract Details

* **Source File:** `src/Pectra.sol`
* **Test File:** `test/Pectra.t.sol`
* **Key Functions:**
    * `batchConsolidation(bytes[] memory sourcePubkeys, bytes memory targetPubkey)`
    * `batchSwitch(bytes[] memory pubkeys)`
    * `batchELExit(bytes[2][] memory data)`
* **Target System Contracts:**
    * `consolidationTarget`: `0x0000BBdDc7CE488642fb579F8B00f3a590007251`
    * `exitTarget`: `0x00000961Ef480Eb55e80D19ad83579A64c007002`
        *(Verify these addresses before use!)*
