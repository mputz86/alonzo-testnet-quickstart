#!/bin/bash

# ======================================================================
# Load funds into collateral wallet
# ===================================
fund_collateral() {
  if [ -z $amount_to_send ]; then
    echo "Error: How much do you want to send?"
    exit 1
  fi

  echo Amount to Send: $amount_to_send

  if (( "$amount_to_send" < "$collateral_value_required" )); then
    echo "Error: Amount to send ($amount_to_send) is insufficient to cover redemption collateral ($collateral_value_required)"
    exit 1
  fi

  # ===================================
  # Fee
  fee=$((200*1000))
  echo Fee: $fee

  required_inflow=$(($fee + $amount_to_send))
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
  inflow=$(echo $main_wallet_utxo_sufficient | jq -r '.value.value.lovelace')
  echo Input Balance: $inflow

  amount_change=$(($inflow - $fee - $amount_to_send))
  echo Amount Change: $amount_change

  if (( "$amount_change" < "0" )); then
    echo "Error: Input Balance ($inflow) is insufficient to pay Amount to Send ($amount_to_send)"
    exit 1
  fi

  # ===================================
  # Inputs and outputs
  tx_in=$(echo $main_wallet_utxo_sufficient | jq -r '.key')
  echo Tx In: $tx_in

  tx_in_signing_key=$(cardano-wallet signing-key main)
  echo Tx In Signing Key: $tx_in_signing_key

  tx_out_change="$(cardano-wallet main)+$amount_change"
  echo Tx Out Change: $tx_out_change

  tx_out_payment="$(cardano-wallet collateral)+$amount_to_send"
  echo Tx Out Payment: $tx_out_payment

  # ===================================
  # Construct transaction
  setup_tx_file
  echo Tx File: $tx_file

  cardano-cli query protocol-parameters --testnet-magic 5 --out-file $tx_file.params

  cardano-cli transaction build-raw --mary-era \
    --out-file $tx_file.unsigned \
    --fee $fee \
    --tx-in $tx_in \
    --tx-out $tx_out_change \
    --tx-out $tx_out_payment

  if [ -f $tx_file.unsigned ]; then
    cardano-cli transaction sign --testnet-magic 5 \
      --out-file $tx_file.signed \
      --tx-body-file $tx_file.unsigned \
      --signing-key-file $tx_in_signing_key

    # cardano-cli transaction view --tx-file $tx_file.signed | yq > /dev/stdout
  fi
}

