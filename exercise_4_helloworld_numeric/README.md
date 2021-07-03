# Exercise 4: Helloworld numeric
In this exercise, you are asked to interact with a slightly less trivial on-chain validator, which succeeds if it is provided with an integer datum `123`, ignoring the redeemer and transaction context:
```haskell
hello :: Data
hello = I 123

helloWorld :: Data -> Data -> Data -> ()
helloWorld datum _ _ = if datum P.== hello then () else (P.error ())
```

This validator has been compiled and serialized and saved at [./plutus/helloworld-numeric.plutus](./plutus/helloworld-numeric.plutus).

As with the previous exercise, the trick with this exercise is making sure that the datum-hash you provide when locking funds under the validator matches the datum that you provide when redeeming funds from the validator. Also, the datum needs to be `123`.

## Difference from Exercise 3
Few adjustments to the exercise 3 files were required to adapt them to this exercise:
- Replace the randomized text datum in `datum.txt` with the numeric datum `123`.
- Replace the `untyped-always-succeeds-txin.plutus` compiled+serialized validator with `helloworld-numeric.plutus`.
- Modify the `$script_file` reference in `scripts/prepare_for_plutus_script.sh`.

```diff
[user@machine exercise_4_helloworld_numeric]$ diff -r -x 'transaction*' -x 'README*' ../exercise_3/ ./
diff -r -x 'transaction*' -x 'README*' ../exercise_3/datum.txt ./datum.txt
1c1
< "CRTTenDIKONBp"
---
> 123
Only in ./plutus: helloworld-numeric.plutus
Only in ./plutus: helloworld-numeric.plutus.budget.json
Only in ../exercise_3/plutus: untyped-always-succeeds-txin.plutus
Only in ../exercise_3/plutus: untyped-always-succeeds-txin.plutus.budget.json
diff -r -x 'transaction*' -x 'README*' ../exercise_3/scripts/prepare_for_plutus_script.sh ./scripts/prepare_for_plutus_script.sh
9c9
<   script_file="./plutus/untyped-always-succeeds-txin.plutus"
---
>   script_file="./plutus/helloworld-numeric.plutus"
```

## Setup for the exercise
Ensure that the passive node is running ([../README.md#run-and-monitor-a-passive-cardano-node](../README.md#run-and-monitor-a-passive-cardano-node))and that the main address has funds before proceeding ([../README.md#wallet-setup-for-exercises](../README.md#wallet-setup-for-exercises)):
```
[user@machine exercise_4_helloworld_numeric]$ cardano-wallet balance main
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
[user@machine exercise_4_helloworld_numeric]$ ./main.sh fund-collateral $((10*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the collateral wallet:
```
[user@machine exercise_4_helloworld_numeric]$ watch -n 10 cardano-wallet balance collateral
```

## Lock funds under the script
Lock some funds under the `plutus-always-succeeds.plutus` script:
```
[user@machine exercise_4_helloworld_numeric]$ ./main.sh lock-funds $((1000*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived at the script address:
```
[user@machine exercise_4_helloworld_numeric]$ watch -n 10 "cardano-wallet balance-script ./plutus/helloworld-numeric.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'"
```

If there are funds already locked under the script with your datum, the `lock-funds` operation will ask you to redeem them first:
```
[user@machine exercise_4_helloworld_numeric]$ ./main.sh lock-funds $((1000*1000*1000))
...
Utxos detected with this datum. It's better to either redeem them first, or choose another datum.
```

## Redeem funds from the script
Redeem the funds under the `plutus-always-succeeds.plutus` script:
```
[user@machine exercise_4_helloworld_numeric]$ ./main.sh redeem-funds
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the main wallet:
```
[user@machine exercise_4_helloworld_numeric]$ watch -n 10 cardano-wallet balance main
```

If there are no funds locked under the script with your datum, then `redeem-funds` operation will let you know that there is nothing to redeem.
```
[user@machine exercise_4_helloworld_numeric]$ ./main.sh redeem-funds
...
No utxos detected with this datum. There is nothing to redeem.
```

## Clean-up
Clean-up generated but unsubmitted transactions, stored in `./tx/`:
```
[user@machine exercise_4_helloworld_numeric]$ ./main.sh clean-tx-log
```

Files for submitted transactions are kept, just in case.
