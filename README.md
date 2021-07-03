# Alonzo testnet starting kit
This repository is intended to help people get started quickly with the Alonzo Testnet. In particular, it contains a fairly robust shell script to lock and then redeem test ADA funds under a simple Plutus Core script.

## Prerequisites
This project has been developed/tested on a Linux system, and it requires the following utilities:
- [direnv](https://direnv.net/)
- [nix](https://nixos.org/guides/install-nix.html)
- [jq](https://stedolan.github.io/jq/)
- [yq](https://kislyuk.github.io/yq/)

## Setup
Clone this repository and enter the resulting directory.

Take a look at the `.envrc` file to see what environment variables and path it sets up. Enable direnv: 
```
user@machine$ direnv allow
```

Install cardano-node and cardano-cli:
```
user@machine$ setup-cardano-node-and-cli.sh
```

## Run and monitor a passive cardano node
Start cardano node:
```
user@machine$ cd $NODE_HOME && cardano-node-alonzo-blue 1>&2> node.log
```

Open another terminal tab to monitor the node. For example, if you have the [lnav](https://lnav.org/) utility installed:
```
user@machine$ lnav -t -c ':goto 100%' $NODE_HOME/node.log
```

## Cardano-wallet utility
The helper script `scripts/cardano-wallet` makes it easier to manage several "wallets" (a wallet includes an address, a payment skey/vkey pair, and a staking skey/vkey pair).

Usage:
```
user@machine$ cardano-wallet --help
cardano-wallet - Helper script to handle "wallets" in
the Alonzo Testnet. A "wallet" is a set of skeys/vkeys
for payment/staking, plus a public address.

Usage: cardano-wallet [OPTIONS] OPERATION (WALLET_ID | SCRIPT_FILE)

Available options:
  -h, --help                     display this help message
  -y, --yes                      do not ask for confirmation of destructive operations

Operations (default = address):
  address WALLET_ID              get the address for the wallet called WALLET_ID
  address-script SCRIPT_FILE     get the address for a script located at SCRIPT_FILE
  balance WALLET_ID              get the balance for the wallet called WALLET_ID
  balance-script SCRIPT_FILE     get the balance for a script located at SCRIPT_FILE
  create WALLET_ID               create a wallet called WALLET_ID
  remove WALLET_ID               remove the wallet called WALLET_ID
  signing-key WALLET_ID          get the signing key for the wallet called WALLET_ID
  verification-key WALLET_ID     get the verification key for the wallet called WALLET_ID
```

## Exercise 3

See: [./exercise_3/README.md](./exercise_3/README.md).
