- [x]  Re-implement Uniswap V2 with the following requirements
- [x]use solidity 0.8.0 or higher. **You need to be conscious of when the original implementation originally intended to overflow in the oracle**
- [x] Use the Solady ERC20 library to accomplish the LP token, also use the Solady library to accomplish the square root
- [x] The uniswap re-entrancy lock is not gas efficient anymore because of changes in the EVM
- Your code should have built-in safety checks for swap, mint, and burn. **You should not assume people will use a router but instead directly interface with your contract**
- [x] The swap function should not support flash swaps, you should build a separate flashloan function that is compliant with ERC-3156
- [x]Don’t use safemath with 0.8.0 or higher
- [x]You should only implement the factory and the pair (which inherits from ERC20), don’t implement other contracts

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
