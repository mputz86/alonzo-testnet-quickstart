# Exercise 3

## Setup for the exercise
Got to the `exercise_3` directory of the repository:
```
user@machine$ cd $NODE_HOME/exercise_3
```

Create a file `datum.txt` to store the datum that you will use for this exercise:
```
user@machine$ echo "\"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)\"" > datum.txt
```

Ensure that the passive node is running ([../README.md#run-and-monitor-a-passive-cardano-node](../README.md#run-and-monitor-a-passive-cardano-node))and that the main address has funds before proceeding ([../README.md#wallet-setup-for-exercises](../README.md#wallet-setup-for-exercises)):
```
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

## Fund a sufficient utxo for collateral
Send some funds to the 'collateral' wallet, which will provide collateral utxos for transactions that consume script-guarded utxos:
```
user@machine$ ./exercise_3.sh fund-collateral $((10*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the collateral wallet:
```
user@machine$ watch -n 10 cardano-wallet balance collateral
```

## Lock funds under the script
Lock some funds under the `plutus-always-succeeds.plutus` script:
```
user@machine$ ./exercise_3.sh lock-funds $((1000*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived at the script address:
```
user@machine$ watch -n 10 "cardano-wallet balance-script ./plutus/untyped-always-succeeds-txin.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'"
```

If there are funds already locked under the script with your datum, the `lock-funds` operation will ask you to redeem them first:
```
user@machine$ ./exercise_3.sh lock-funds $((1000*1000*1000))
...
Utxos detected with this datum. It's better to either redeem them first, or choose another datum.
```

## Redeem funds from the script
Redeem the funds under the `plutus-always-succeeds.plutus` script:
```
user@machine$ ./exercise_3.sh redeem-funds
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the main wallet:
```
user@machine$ watch -n 10 cardano-wallet balance main
```

If there are no funds locked under the script with your datum, then `redeem-funds` operation will let you know that there is nothing to redeem.
```
user@machine$ ./exercise_3.sh redeem-funds
...
No utxos detected with this datum. There is nothing to redeem.
```

## Clean-up
Clean-up generated but unsubmitted transactions, stored in `./tx/`:
```
user@machine$ ./exercise_3.sh clean-tx-log
```

