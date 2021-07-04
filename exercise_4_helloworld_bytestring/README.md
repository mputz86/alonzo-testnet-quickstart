# Exercise 4: Helloworld bytestring
In this exercise, you are asked to interact with a slightly more complicated on-chain validator, which succeeds if it is provided with a text datum `"Hello World!"`, ignoring the redeemer and transaction context. For various technical reasons, this validator had to be written in parametric form, where the keyword to which the datum is compared is passed in as an additional argument.
```haskell
hello :: P.ByteString
hello = "Hello World!"

helloWorld :: P.ByteString -> P.ByteString -> P.ByteString -> ScriptContext -> P.Bool
helloWorld keyword datum _ _ = keyword P.== datum

data HelloWorld
instance Scripts.ScriptType HelloWorld where
    type instance DatumType HelloWorld = P.ByteString
    type instance RedeemerType HelloWorld = P.ByteString

helloWorldInstance :: Scripts.ScriptInstance HelloWorld
helloWorldInstance = Scripts.validator @HelloWorld
    ($$(PlutusTx.compile [|| helloWorld ||]) `PlutusTx.applyCode` PlutusTx.liftCode hello)
    $$(PlutusTx.compile [|| wrap ||])
  where
    wrap = Scripts.wrapValidator @P.ByteString @P.ByteString
```

This validator has been compiled and serialized and saved at [./plutus/helloworld-bytestring.plutus](./plutus/helloworld-bytestring.plutus).

As with the previous exercise, the trick with this exercise is making sure that the datum-hash you provide when locking funds under the validator matches the datum that you provide when redeeming funds from the validator. Also, the datum needs to be `"Hello World!"`.

## Difference from Exercise 4 (Helloworld Numeric)
A few adjustments to the exercise 4 (numeric validator) files were required to adapt them to this exercise:
- Replace the the numeric datum `123` with the text datum `"Hello World!"`.
- Replace the `helloworld-numeric.plutus` compiled+serialized validator with `helloworld-bytestring.plutus`.
- Modify the `$script_file` reference in `scripts/prepare_for_plutus_script.sh`.
- Increase the `$scalar_factor` from 20 to 40. This scalar factor is used to multiplicative scale up the (Steps, Memory) units defined in `helloworld-bytestring.plutus.budget.json`, which the compiler calculated for the script. (Not sure why the compiler's calculated units are not sufficient and have to be scaled up, in the first place...)

```diff
[user@machine exercise_4_helloworld_bytestring]$ iff -r -x 'transaction*' -x 'README*' ../exercise_4_helloworld_numeric/ ./
diff -r -x 'transaction*' -x 'README*' ../exercise_4_helloworld_numeric/datum.txt ./datum.txt
1c1
< 123
---
> "Hello World!"
Only in ./plutus: helloworld-bytestring.plutus
Only in ./plutus: helloworld-bytestring.plutus.budget.json
Only in ../exercise_4_helloworld_numeric/plutus: helloworld-numeric.plutus
Only in ../exercise_4_helloworld_numeric/plutus: helloworld-numeric.plutus.budget.json
diff -r -x 'transaction*' -x 'README*' ../exercise_4_helloworld_numeric/scripts/prepare_for_plutus_script.sh ./scripts/prepare_for_plutus_script.sh
9c9
<   script_file="./plutus/helloworld-numeric.plutus"
---
>   script_file="./plutus/helloworld-bytestring.plutus"
54c54
<   scalar_factor=20
---
>   scalar_factor=40
```

## Setup for the exercise
Ensure that the passive node is running ([../README.md#run-and-monitor-a-passive-cardano-node](../README.md#run-and-monitor-a-passive-cardano-node))and that the main address has funds before proceeding ([../README.md#wallet-setup-for-exercises](../README.md#wallet-setup-for-exercises)):
```
[user@machine exercise_4_helloworld_bytestring]$ cardano-wallet balance main
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
[user@machine exercise_4_helloworld_bytestring]$ ./main.sh fund-collateral $((44*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the collateral wallet:
```
[user@machine exercise_4_helloworld_bytestring]$ watch -n 10 cardano-wallet balance collateral
```

## Lock funds under the validator script
Lock some funds under the validator script:
```
[user@machine exercise_4_helloworld_bytestring]$ ./main.sh lock-funds $((2200*1000*1000))
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived at the script address:
```
[user@machine exercise_4_helloworld_bytestring]$ watch -n 10 "cardano-wallet balance-script ./plutus/helloworld-bytestring.plutus \
  | jq 'map_values(select(.data != null) | {lovelace: .value.lovelace, data: .data})'"
```

If there are funds already locked under the script with your datum, the `lock-funds` operation will ask you to redeem them first:
```
[user@machine exercise_4_helloworld_bytestring]$ ./main.sh lock-funds $((2200*1000*1000))
...
Utxos detected with this datum. It's better to either redeem them first, or choose another datum.
```

## Redeem funds from the validator script
Redeem the funds under the validator script:
```
[user@machine exercise_4_helloworld_bytestring]$ ./main.sh redeem-funds
...
Are you sure you want to submit this transaction (y/n)? y
```

Check whether the funds arrived in the main wallet:
```
[user@machine exercise_4_helloworld_bytestring]$ watch -n 10 cardano-wallet balance main
```

If there are no funds locked under the script with your datum, then `redeem-funds` operation will let you know that there is nothing to redeem.
```
[user@machine exercise_4_helloworld_bytestring]$ ./main.sh redeem-funds
...
No utxos detected with this datum. There is nothing to redeem.
```

## Clean-up
Clean-up generated but unsubmitted transactions, stored in `./tx/`:
```
[user@machine exercise_4_helloworld_bytestring]$ ./main.sh clean-tx-log
```

Files for submitted transactions are kept, just in case.
