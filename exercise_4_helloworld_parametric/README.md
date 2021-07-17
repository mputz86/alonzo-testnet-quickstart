# Exercise 4: Helloworld parametric
In this exercise, you are asked to interact with a slightly more complicated on-chain validator, which succeeds if it is provided with a text datum `"Hello World!"`, ignoring the redeemer and transaction context. For various technical reasons, this validator had to be written in parametric form, where the keyword to which the datum is compared is passed in as an additional argument.
```haskell
hello :: P.ByteString
hello = "Hello World!"

{-# INLINABLE helloWorld #-}
helloWorld :: P.ByteString -> P.ByteString -> P.ByteString -> ScriptContext -> P.Bool
helloWorld keyword datum redeemer context = keyword P.== datum

data HelloWorld
instance Scripts.ValidatorTypes HelloWorld where
    type instance DatumType HelloWorld = P.ByteString
    type instance RedeemerType HelloWorld = P.ByteString

helloWorldInstance :: Scripts.TypedValidator HelloWorld
helloWorldInstance = Scripts.mkTypedValidator @HelloWorld
    ($$(PlutusTx.compile [|| helloWorld ||]) `PlutusTx.applyCode` PlutusTx.liftCode hello)
    $$(PlutusTx.compile [|| wrap ||])
  where
    wrap = Scripts.wrapValidator @P.ByteString @P.ByteString
```

This validator has been compiled and serialized and saved at [./plutus/helloworld-parametric.plutus](./plutus/helloworld-parametric.plutus).

As with the previous exercise, the trick with this exercise is making sure that the datum-hash you provide when locking funds under the validator matches the datum that you provide when redeeming funds from the validator. Also, the datum needs to be `"Hello World!"`.

## Difference from Exercise 3
A few adjustments to the exercise 3 files were required to adapt them to this exercise:
- Replace the the random datum with the specific text datum `"Hello World!"`.
- Replace the `untyped-always-succeeds-txin.plutus` compiled+serialized validator with `helloworld-parametric.plutus`.
- Modify the `$script_file` reference in `scripts/prepare_for_plutus_script.sh`.
- Increase the `$scalar_factor` from 20 to 30. This scalar factor is used to multiplicatively scale up the (Steps, Memory) units defined in `helloworld-parametric.plutus.budget.json`, which the compiler calculated for the script. (Not sure why the compiler's calculated units are not sufficient and have to be scaled up, in the first place...)

```diff
[user@machine exercise_4_helloworld_parametric]$ diff -r -x 'transaction*' -x 'README*' ../exercise_3/ ./
diff -r -x 'transaction*' -x 'README*' ../exercise_3/datum.txt ./datum.txt
1c1
< "yqSxqRacAwq1A"
---
> "Hello World!"
Only in ./plutus: helloworld-parametric.plutus
Only in ./plutus: helloworld-parametric.plutus.budget.json
Only in ../exercise_3/plutus: untyped-always-succeeds-txin.plutus
Only in ../exercise_3/plutus: untyped-always-succeeds-txin.plutus.budget.json
diff -r -x 'transaction*' -x 'README*' ../exercise_3/scripts/prepare_for_plutus_script.sh ./scripts/prepare_for_plutus_script.sh
9c9
<   script_file="./plutus/untyped-always-succeeds-txin.plutus"
---
>   script_file="./plutus/helloworld-parametric.plutus"
54c54
<   scalar_factor=20
---
>   scalar_factor=30
```

## Setup for the exercise
Ensure that the passive node is running ([../README.md#run-and-monitor-a-passive-cardano-node](../README.md#run-and-monitor-a-passive-cardano-node))and that the main address has funds before proceeding ([../README.md#wallet-setup-for-exercises](../README.md#wallet-setup-for-exercises)):
```
[user@machine exercise_4_helloworld_parametric]$ cardano-wallet utxos main
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
[user@machine exercise_4_helloworld_parametric]$ ./main.sh fund-collateral $((9*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the collateral wallet:
```
[user@machine exercise_4_helloworld_parametric]$ watch -n 10 cardano-wallet utxos collateral
```

## Lock funds under the validator script
Lock some funds under the validator script:
```
[user@machine exercise_4_helloworld_parametric]$ ./main.sh lock-funds $((850*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived at the script address:
```
[user@machine exercise_4_helloworld_parametric]$ watch -n 10 "cardano-wallet utxos-script ./plutus/helloworld-parametric.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'"
```

If there are funds already locked under the script with your datum, the `lock-funds` operation will ask you to redeem them first:
```
[user@machine exercise_4_helloworld_parametric]$ ./main.sh lock-funds $((850*1000*1000))
...
Utxos detected with this datum. It's better to either redeem them first, or choose another datum.
```

## Redeem funds from the validator script
Redeem the funds under the validator script:
```
[user@machine exercise_4_helloworld_parametric]$ ./main.sh redeem-funds
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the main wallet:
```
[user@machine exercise_4_helloworld_parametric]$ watch -n 10 cardano-wallet utxos main
```

Note that since everyone is using the same datum with this script, there may still be some funds locked under the script that you can redeem with your datum. Please be respectful to others. You can check the utxos under the script address as follows:
```
[user@machine exercise_4_helloworld_parametric]$ cardano-wallet utxos-script ./plutus/helloworld-parametric.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'
```

If there are no funds locked under the script with your datum, then `redeem-funds` operation will let you know that there is nothing to redeem.
```
[user@machine exercise_4_helloworld_parametric]$ ./main.sh redeem-funds
...
No utxos detected with this datum. There is nothing to redeem.
```

Double-check that you didn't lose your collateral utxo:
```
[user@machine exercise_4_helloworld_parametric]$ cardano-wallet utxos collateral
```

## Clean-up
Clean-up generated but unsubmitted transactions, stored in `./tx/`:
```
[user@machine exercise_4_helloworld_parametric]$ ./main.sh clean-tx-log
```

Files for submitted transactions are kept, just in case.
