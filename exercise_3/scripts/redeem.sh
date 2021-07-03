#!/bin/bash

# ======================================================================
# Redeem funds from script
# ===================================
redeem_funds() {
  # ===================================
  # Script utxo selection
  script_utxo_with_my_datum=$(balance $(cat $script_address_file) --out-file /dev/stdout \
    | jq --arg utxo $datum_hash 'to_entries | map(select(.value.data == $utxo))' \
    | jq 'max_by(.value.value.lovelace)')
  echo Script Utxo with My Datum:
  echo $script_utxo_with_my_datum

  if [ "$script_utxo_with_my_datum" == 'null' ]; then
    echo "No utxos detected with this datum. There is nothing to redeem."
    exit 1
  fi

  # ===================================
  # Fee
  fee=$scaled_redemption_cost
  echo Fee: $fee

  required_inflow=$(($fee))
  echo Required Inflow: $required_inflow

  # ===================================
  # Wallet utxo selection
  main_wallet_utxo_sufficient=$(cardano-wallet balance main \
    | jq --argjson payment "$required_inflow" 'to_entries | map(select(.value.value.lovelace >= $payment))' \
    | jq 'min_by(.value.value.lovelace)')
  echo Main Wallet: $(cardano-wallet main)
  echo Main Wallet Sufficient Utxo:
  echo $main_wallet_utxo_sufficient

  # ===================================
  # Lovelace inflow and outflow
  echo Main Wallet: $(cardano-wallet main)

  inflow_script=$(echo $script_utxo_with_my_datum | jq -r '.value.value.lovelace')
  echo "Inflow (Script): $inflow_script"

  inflow_main=$(echo $main_wallet_utxo_sufficient | jq -r '.value.value.lovelace')
  echo "Inflow (Main): $inflow_main"

  inflow=$(($inflow_script + $inflow_main))
  echo "Inflow (Total): $inflow"

  amount_change=$(($inflow - $fee))
  echo Amount Change: $amount_change

  if (( "$amount_change" < "0" )); then
    echo "Error: Transcation inflow funds ($inflow) are insufficient to pay the fee ($fee)"
    exit 1
  fi

  # ===================================
  # Collateral selection
  collateral_utxo_sufficient=$(cardano-wallet balance collateral \
    | jq --argjson required $collateral_value_required 'to_entries | map(select(.value.value.lovelace >= $required))' \
    | jq 'min_by(.value.value.lovelace)')
  echo Utxo with Sufficient Collateral:
  echo $collateral_utxo_sufficient

  if [ "$collateral_utxo_sufficient" == 'null' ]; then
    echo "No utxos detected with sufficient collateral. Load the collateral wallet with more funds before proceeding."
    exit 1
  fi

  # ===================================
  # Inputs and outputs
  tx_in_main=$(echo $main_wallet_utxo_sufficient | jq -r '.key')
  tx_in_main_value=$(echo $main_wallet_utxo_sufficient | jq -r '.value.value.lovelace')
  echo "Tx In (Main): $tx_in_main ($tx_in_main_value)"

  tx_in_main_signing_key=$(cardano-wallet signing-key main)
  echo "Tx In (Main) Signing Key: $tx_in_main_signing_key"

  tx_in_script=$(echo $script_utxo_with_my_datum | jq -r '.key')
  tx_in_script_value=$(echo $script_utxo_with_my_datum | jq -r '.value.value.lovelace')
  echo "Tx In (Script): $tx_in_script ($tx_in_script_value)"

  tx_in_collateral=$(echo $collateral_utxo_sufficient | jq -r '.key')
  tx_in_collateral_value=$(echo $collateral_utxo_sufficient | jq -r '.value.value.lovelace')
  echo "Tx In (Collateral): $tx_in_collateral ($tx_in_collateral_value)"

  tx_in_collateral_signing_key=$(cardano-wallet signing-key collateral)
  echo "Tx In (Collateral) Signing Key: $tx_in_collateral_signing_key"

  tx_out_change="$(cardano-wallet main)+$amount_change"
  echo "Tx Out (Main) Change: $tx_out_change"

  # ===================================
  # Construct transaction
  setup_tx_file
  echo Tx File: $tx_file

  cardano-cli query protocol-parameters --testnet-magic 5 --out-file $tx_file.params

  cardano-cli transaction build-raw --alonzo-era \
    --out-file $tx_file.unsigned \
    --fee $fee \
    --protocol-params-file $tx_file.params \
    --tx-in $tx_in_main \
    --tx-in $tx_in_script \
    --tx-in-script-file $script_file \
    --tx-in-datum-value $datum \
    --tx-in-redeemer-value $datum \
    --tx-in-execution-units "$execution_units" \
    --tx-in-collateral $tx_in_collateral \
    --tx-out $tx_out_change

  if [ -f $tx_file.unsigned ]; then
    cardano-cli transaction sign --testnet-magic 5 \
      --out-file $tx_file.signed \
      --tx-body-file $tx_file.unsigned \
      --signing-key-file $tx_in_main_signing_key \
      --signing-key-file $tx_in_collateral_signing_key
  fi
}
