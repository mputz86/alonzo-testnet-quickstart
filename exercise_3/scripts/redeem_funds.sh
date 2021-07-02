#!/bin/bash

# ======================================================================
# Redeem funds from script
# ===================================
redeem_funds() {
  if [ $utxos_with_my_datum_len -eq 0 ]; then
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
  # Lovelace inflow and outflow
  echo Main Wallet: $(cardano-wallet main)

  inflow=$(echo $utxos_with_my_datum | jq '.[0].value.value.lovelace')
  echo Inflow: $inflow

  amount_change=$(($inflow - $fee))
  echo Amount Change: $amount_change

  if (( "$amount_change" < "0" )); then
    echo "Error: Input Balance ($inflow) is insufficient to pay the fee ($fee)"
    exit 1
  fi

  # ===================================
  # Collateral selection
  utxos_with_sufficient_collateral=$(cardano-wallet balance collateral | \
    jq -r --argjson required $collateral_value_required 'to_entries | map(select(.value.value.lovelace >= $required))')
  utxos_with_sufficient_collateral_len=$(echo $utxos_with_my_datum | jq 'length')
  echo Utxos with Sufficient Collateral: $utxos_with_sufficient_collateral_len
  echo $utxos_with_sufficient_collateral

  if [ $utxos_with_sufficient_collateral_len -eq 0 ]; then
    echo "No utxos detected with sufficient collateral. Load the collateral wallet with more funds before proceeding."
    exit 1
  fi

  # ===================================
  # Inputs and outputs
  tx_in=$(echo $utxos_with_my_datum | jq -r '.[0].key')
  tx_in_value=$(echo $utxos_with_my_datum | jq -r '.[0].value.value.lovelace')
  echo "Tx In: $tx_in ($tx_in_value)"

  tx_in_collateral=$(echo $utxos_with_sufficient_collateral | jq -r '.[0].key')
  tx_in_collateral_value=$(echo $utxos_with_sufficient_collateral | jq -r '.[0].value.value.lovelace')
  echo "Tx In Collateral: $tx_in_collateral ($tx_in_collateral_value)"

  tx_in_collateral_signing_key=$(cardano-wallet signing-key collateral)
  echo Tx In Collateral Signing Key: $tx_in_collateral_signing_key

  tx_out_change="$(cardano-wallet main)+$amount_change"
  echo Tx Out Change: $tx_out_change

  # ===================================
  # Construct transaction
  setup_tx_file
  echo Tx File: $tx_file

  cardano-cli transaction build-raw --alonzo-era \
    --out-file $tx_file.unsigned \
    --fee $fee \
    --protocol-params-file $params_file \
    --tx-in $tx_in \
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
      --signing-key-file $tx_in_collateral_signing_key
  fi
}

