#!/bin/bash

# ======================================================================
# Utility functions
# ===================================
echoerr (){
  cat <<< "$@" 1>&2;
}

balance_at_address (){
  cardano-cli query utxo --testnet-magic 5 --out-file /dev/stdout --address "$1"
}

# ======================================================================
# Script and datum
# ===================================
script_file="../plutus/AlwaysSucceeds.plutus"
echoerr Script File: $script_file

cardano-cli address build --testnet-magic 5 --out-file script.addr --payment-script-file $script_file
script_address=$(cat script.addr)
echoerr Script Address: $script_address

datum=$(cat ../random_datum.txt)
echoerr Datum: $datum

datum_hash=$(cat ../random_datum_hash.txt)
echoerr Datum Hash: $datum_hash

# ======================================================================
# Script Input
# ===================================
my_script_utxo_balance=$(balance_at_address $script_address | jq -r --arg hash $datum_hash 'to_entries | .[] | select(.value.data == $hash)')
echoerr My script UTXO Balance:
echoerr $my_script_utxo_balance

tx_in_script=$(echo $my_script_utxo_balance | jq -r '.key')
echoerr Tx In: $tx_in_script

# ======================================================================
# Extra input to cover fees (script balance is insufficient)
# ===================================
my_largest_utxo_balance=$(cardano-wallet balance 2 | jq -r 'to_entries | max_by(.value.value.lovelace)')
echoerr Largest UTXO Balance:
echoerr $my_largest_utxo_balance

tx_in_extra=$(echo $my_largest_utxo_balance | jq -r '.key')
echoerr Tx In Extra: $tx_in_extra

tx_in_extra_witness=$(cardano-wallet signing-key 2)
echoerr Tx In Extra Witness: $tx_in_extra_witness

# ======================================================================
# Collateral Input
# ===================================
collateral_utxo_balance=$(cardano-wallet balance 2 | jq -r 'to_entries | min_by(.value.value.lovelace)')
echoerr Collateral UTXO Balance:
echoerr $collateral_utxo_balance

tx_in_collateral=$(echo $collateral_utxo_balance | jq -r '.key')
echoerr Tx In Collateral: $tx_in_collateral

tx_in_collateral_witness=$(cardano-wallet signing-key 2)
echoerr Tx In Collateral Witness: $tx_in_collateral_witness

# ======================================================================
# Fees and outputs
# ===================================
input_balance=$( (echo $my_script_utxo_balance; echo $my_largest_utxo_balance) | jq -r --slurp 'map(.value.value.lovelace) | add')
echoerr Input Balance: $input_balance

execution_units=$((10*1000*1000*1000))
step_units=$execution_units
memory_units=$execution_units
echoerr Execution Units: "($step_units, $memory_units)"

fee_size=$((1000*1000))
fee_execution=$(cat ../params.json | jq -r --argjson steps $step_units --argjson memory $memory_units \
  '.executionUnitPrices | [.priceSteps * $steps, .priceMemory * $memory] | add')
fee=$(($fee_size + $fee_execution))
echoerr "Fee (Calculated): $fee = $fee_execution + $fee_size"

amount_to_send=$(($input_balance - $fee))
echoerr Amount to Send: $amount_to_send

tx_out_payment="$(cardano-wallet 2)+$amount_to_send"
echoerr Tx Out Payment: $tx_out_payment

# ======================================================================
# Build and sign the transaction
# ===================================
(echo "cardano-cli transaction build-raw --alonzo-era --protocol-params-file ../params.json \
  --out-file tx.unsigned \
  --fee $fee \
  --tx-in $tx_in_extra \
  --tx-in $tx_in_script \
  --tx-in-script-file $script_file \
  --tx-in-datum-value $datum \
  --tx-in-redeemer-value \"[]\" \
  --tx-in-execution-units \"($step_units, $memory_units)\" \
  --tx-in-collateral $tx_in_collateral \
  --tx-out $tx_out_payment"; \
\
echo "cardano-cli transaction sign --testnet-magic 5 \
  --out-file tx.signed \
  --tx-body-file tx.unsigned \
  --signing-key-file $tx_in_collateral_witness" \
) > cli-commands.sh

source cli-commands.sh
