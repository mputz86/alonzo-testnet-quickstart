# Exercise 3
In this exercise, you are asked to interact with the most trivial on-chain validator, which succeeds regardless of the (datum, redeemer, transaction context) that it is provided with:
```haskell
validator :: Data -> Data -> Data -> ()
validator _ _ _ = ()
```

This validator has been compiled and serialized and saved at [./plutus/always-succeeds.plutus](./plutus/always-succeeds.plutus).

The trick with this exercise is making sure that the datum-hash you provide when locking funds under the validator matches the datum that you provide when redeeming funds from the validator.

## Setup for the exercise
Create a file `datum.txt` to store the datum that you will use for this exercise:
```
[user@machine exercise_3]$ echo "\"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)\"" > datum.txt
```

Ensure that the passive node is running ([../README.md#run-and-monitor-a-passive-cardano-node](../README.md#run-and-monitor-a-passive-cardano-node))and that the main address has funds before proceeding ([../README.md#wallet-setup-for-exercises](../README.md#wallet-setup-for-exercises)):
```
[user@machine exercise_3]$ cardano-wallet balance main
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
[user@machine exercise_3]$ ./main.sh fund-collateral $((3*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the collateral wallet:
```
[user@machine exercise_3]$ watch -n 10 cardano-wallet balance collateral
```

## Lock funds under the validator script
Lock some funds under the validator script:
```
[user@machine exercise_3]$ ./main.sh lock-funds $((120*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived at the script address:
```
[user@machine exercise_3]$ watch -n 10 "cardano-wallet balance-script ./plutus/always-succeeds.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'"
```

If there are funds already locked under the script with your datum, the `lock-funds` operation will ask you to redeem them first:
```
[user@machine exercise_3]$ ./main.sh lock-funds $((120*1000*1000))
...
Utxos detected with this datum. It's better to either redeem them first, or choose another datum.
```

## Redeem funds from the validator script
Redeem the funds under the validator script:
```
[user@machine exercise_3]$ ./main.sh redeem-funds
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the main wallet:
```
[user@machine exercise_3]$ watch -n 10 cardano-wallet balance main
```

Alternatively, you can check whether the funds left the script address:
```
[user@machine exercise_3]$ watch -n 10 "cardano-wallet balance-script ./plutus/always-succeeds.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'"
```

If there are no funds locked under the script with your datum, then `redeem-funds` operation will let you know that there is nothing to redeem.
```
[user@machine exercise_3]$ ./main.sh redeem-funds
...
No utxos detected with this datum. There is nothing to redeem.
```

Double-check that you didn't lose your collateral utxo:
```
[user@machine exercise_3]$ cardano-wallet balance collateral
```

## Clean-up
Clean-up generated but unsubmitted transactions, stored in `./tx/`:
```
[user@machine exercise_3]$ ./main.sh clean-tx-log
```

Files for submitted transactions are kept, just in case.
