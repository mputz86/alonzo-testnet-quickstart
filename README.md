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
```bash
user@machine$ direnv allow
```

Install cardano-node and cardano-cli:
```bash
user@machine$ setup-cardano-node-and-cli.sh
```

## Run and monitor a passive cardano node
Start cardano node:
```bash
user@machine$ cd $NODE_HOME && cardano-node-alonzo-blue 1>&2> node.log
```

Open another terminal tab to monitor the node. For example, if you have the [lnav](https://lnav.org/) utility installed:
```bash
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
Go to the `exercise_3` directory:
```bash
user@machine$ cd exercise_3
```

Create a file `datum.txt` to store the datum that you will use for this exercise:
```bash
user@machine$ echo "\"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)\"" > datum.txt
```

Create two wallets 'main' and 'collateral':
```bash
user@machine$ cardano-wallet create main
Creating wallet main at $NODE_HOME/wallet/main

user@machine$ cardano-wallet create collateral
Creating wallet main at $NODE_HOME/wallet/collateral
```

Beg friends/family for Alonzo testnet ADA, which should be sent to the 'main' address:
```bash
user@machine$ echo $(cardano-wallet main)
addr_test...
```

Ensure that the passive node is running (see above) and that the main address has funds before proceeding.
```bash
user@machine$ cardano-wallet balance main
{
   "...#...": {
     "address": "addr_test....",
     "value": {
       "lovelace": ...
     }
   }
}
```

Send some funds to the 'collateral' wallet, which will provide collateral utxos for transactions that consume script-guarded utxos:
```bash
user@machine$ ./exercise_3.sh fund-collateral $((10*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the collateral wallet:
```bash
user@machine$ watch -n 10 cardano-wallet balance collateral
```

Lock some funds under the `plutus-always-succeeds.plutus` script:
```bash
user@machine$ ./exercise_3.sh lock-funds $((1000*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived at the script address:
```bash
user@machine$ watch -n 10 "cardano-wallet balance-script ./plutus/untyped-always-succeeds-txin.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'"
```

If there are funds already locked under the script with your datum, the `lock-funds` operation will ask you to redeem them first:
```bash
user@machine$ ./exercise_3.sh lock-funds $((1000*1000*1000))
...
Utxos detected with this datum. It's better to either redeem them first, or choose another datum.
```

Redeem the funds under the `plutus-always-succeeds.plutus` script:
```bash
user@machine$ ./exercise_3.sh redeem-funds
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the main wallet:
```bash
user@machine$ watch -n 10 cardano-wallet balance main
```

If there are no funds locked under the script with your datum, the `redeem-funds` operation will as you to lock some first:
```bash
user@machine$ ./exercise_3.sh redeem-funds
...
No utxos detected with this datum. There is nothing to redeem.
```

Clean-up generated but unsubmitted transactions, stored in `./tx/`:
```bash
user@machine$ ./exercise_3.sh clean-tx-log
```

