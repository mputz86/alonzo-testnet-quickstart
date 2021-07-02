#!/bin/bash

# ======================================================================
# Lock funds into script
# ===================================
lock_funds() {
  if [ -z $amount_to_send ]; then
    echo "Error: How much do you want to send?"
    exit 1
  fi

  echo Amount to Send: $amount_to_send

  if [ $utxos_with_my_datum_len -ne 0 ]; then
    echo "Utxos detected with this datum. It's better to either redeem them first, or choose another datum."
    exit 1
  fi

  if (( "$amount_to_send" < "$scaled_redemption_cost" )); then
    echo "Error: Amount to send ($amount_to_send) is insufficient to cover redemption cost ($scaled_redemption_cost)"
    exit 1
  fi

  # ===================================
  # Fee
  fee=$locking_fee
  echo Fee: $fee

  required_inflow=$(($fee + $amount_to_send + $scaled_redemption_cost))
  echo Required Inflow: $required_inflow

  # ===================================
  # Wallet utxo selection
  main_wallet_utxos_sufficient=$(cardano-wallet balance main | \
    jq -r --argjson payment "$required_inflow" \
    'to_entries | map(select(.value.value.lovelace >= $payment))')
  main_wallet_utxos_sufficient_len=$(echo $main_wallet_utxos_sufficient | jq 'length')
  echo Main Wallet: $(cardano-wallet main)
  echo Main Wallet Sufficient Utxos: $main_wallet_utxos_sufficient_len
  echo $main_wallet_utxos_sufficient

  # ===================================
  # Lovelace inflow and outflow
  inflow=$(echo $main_wallet_utxos_sufficient | jq -r '.[0].value.value.lovelace')
  echo Input Balance: $inflow

  amount_change=$(($inflow - $fee - $amount_to_send))
  echo Amount Change: $amount_change

  if (( "$amount_change" < "0" )); then
    echo "Error: Input Balance ($inflow) is insufficient to pay Amount to Send ($amount_to_send)"
    exit 1
  fi

  # ===================================
  # Inputs and outputs
  tx_in=$(echo $main_wallet_utxos_sufficient | jq -r '.[0].key')
  echo Tx In: $tx_in

  tx_in_signing_key=$(cardano-wallet signing-key main)
  echo Tx In Signing Key: $tx_in_signing_key

  tx_out_change="$(cardano-wallet main)+$amount_change"
  echo Tx Out Change: $tx_out_change

  tx_out_payment="$script_address+$amount_to_send"
  echo Tx Out Payment: $tx_out_payment

  # ===================================
  # Construct transaction
  setup_tx_file
  echo Tx File: $tx_file

  cardano-cli query protocol-parameters --testnet-magic 5 --out-file $tx_file.params

  cardano-cli transaction build-raw --alonzo-era \
    --out-file $tx_file.unsigned \
    --fee $fee \
    --protocol-params-file $tx_file.params \
    --tx-in $tx_in \
    --tx-out $tx_out_change \
    --tx-out $tx_out_payment \
    --tx-out-datum-hash $datum_hash

  if [ -f $tx_file.unsigned ]; then
    cardano-cli transaction sign --testnet-magic 5 \
      --out-file $tx_file.signed \
      --tx-body-file $tx_file.unsigned \
      --signing-key-file $tx_in_signing_key
  fi
}

