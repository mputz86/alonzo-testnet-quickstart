#!/bin/bash

# ======================================================================
# Common for locking and redemption
# ===================================
common() {
  tx_name="$(date +'%Y-%m-%d_%T')_$(basename $0 .sh)_$operation"
  echo Tx Name: $tx_name

  # ===================================
  # Script and datum
  script_file='./plutus/untyped-always-succeeds-txin.plutus'
  script_address_file="$script_file.addr"
  script_budget_file="$script_file.budget.json"
  if [ ! -f "$script_file" ] || [ ! -f "$script_budget_file" ]; then
    echo "Script files do not exist!"
    exit 1
  fi

  cardano-cli address build --testnet-magic 5 --payment-script-file $script_file --out-file $script_address_file
  script_address=$(cat $script_address_file)
  echo Script File: $script_file
  echo Script Address File: $script_address_file
  echo Script Address: $script_address

  datum='"coolness"'
  datum_hash=$(cardano-cli transaction hash-script-data --script-data-value '"coolness"')
  echo Datum: $datum
  echo Datum Hash: $datum_hash

  # ===================================
  # Script utxo selection
  utxos_with_my_datum=$(balance $(cat $script_address_file) --out-file /dev/stdout | \
    jq --arg utxo $datum_hash 'to_entries | map(select(.value.data == $utxo))')
  utxos_with_my_datum_len=$(echo $utxos_with_my_datum | jq 'length')
  echo Utxos with My Datum: $utxos_with_my_datum_len
  echo $utxos_with_my_datum

  # ===================================
  # Locking cost
  locking_fee=$((250*1000))
  echo Locking fee: $locking_fee

  # ===================================
  # Redemption cost
  fixed_cost=$((1000*1000))
  echo Fixed cost: $fixed_cost

  min_execution_units=$(cat $script_budget_file | jq)

  min_redemption_cost=$(jq -n \
    --argjson fixed_cost $fixed_cost \
    --argjson prices "$(cat params.json | jq '.executionUnitPrices')" \
    --argjson budget "$min_execution_units" \
    '{"Steps": ($prices.priceSteps * $budget.Steps), "Memory": ($prices.priceMemory * $budget.Memory)} | add + $fixed_cost')
  echo Minimum Cost to Redeem: $min_redemption_cost

  scalar_factor=100
  scaled_execution_units=$(echo $min_execution_units | jq --argjson factor $scalar_factor 'map_values(. * $factor)')
  scaled_redemption_cost=$(($min_redemption_cost * $scalar_factor))
  echo "Scalar factor: $scalar_factor"
  echo "Scaled-up Execution Units to Redeem (just in case): $scaled_execution_units"
  echo "Scaled-up Cost to Redeem (just in case): $scaled_redemption_cost"

  execution_units="($(echo $scaled_execution_units | jq -r 'join (", ")'))"
  echo Execution Units: $execution_units

  # ===================================
  # Required collateral
  collateral_percentage=$(cat params.json | jq '.collateralPercentage')
  collateral_value_required=$(($scaled_redemption_cost * $collateral_percentage / 100))
  echo Collateral Percentage Required: $collateral_percentage%
  echo Collateral Value Required: $collateral_value_required
}

# ======================================================================
# Locking funds into script
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
  cardano-cli transaction build-raw --alonzo-era \
    --out-file tx/$tx_name.unsigned \
    --fee $fee \
    --protocol-params-file params.json \
    --tx-in $tx_in \
    --tx-out $tx_out_change \
    --tx-out $tx_out_payment \
    --tx-out-datum-hash $datum_hash

  if [ -f tx/$tx_name.unsigned ]; then
    cardano-cli transaction sign --testnet-magic 5 \
      --out-file tx/$tx_name.signed \
      --tx-body-file tx/$tx_name.unsigned \
      --signing-key-file $tx_in_signing_key
  fi
}

# ======================================================================
# Submit transaction
# ===================================
submit() {
  if [ -f tx/$tx_name.signed ]; then
    read -p "Are you sure you want to submit this transaction (y/n)? " -n 1 -r confirmation
    echo ""
    if [[ $confirmation =~ ^[Yy]$ ]]; then
      touch tx/$tx_name.submitted
      cardano-cli transaction submit --testnet-magic 5 --tx-file tx/$tx_name.signed
    fi
  fi
}

# ======================================================================
# Utilities
# ===================================
balance() {
  if [ "$#" -eq 0 ]; then
    echo "Missing address argument to 'balance/1'"
    exit 1
  fi
  cardano-cli query utxo --testnet-magic 5 --address "$1" --out-file /dev/stdout
}

clean_tx_log() {
  cd tx
  transactions=$(ls | \
    jq -R | \
    jq --slurp 'map(capture("(?<name>.+)\\.(?<ext>\\w+)$")) | group_by(.name)' | \
    jq 'map(select(map(.ext) | contains(["submitted"]) | not))' | \
    jq 'flatten | map("\(.name).\(.ext)") | join (" ")' | \
    jq -r)
  if [ ! -z "$transactions" ]; then
    rm --verbose $transactions
  fi
}

# ======================================================================
# Main program
# ===================================
main() {
  case $operation in
    lock)
      common && lock_funds && submit
      ;;
    clean-tx-log)
      clean_tx_log
      ;;
    *)
      echo "Programming error: command $operation is not implemented."
      exit 201
      ;;
  esac

}

# ======================================================================
# Parse command-line arguments
# ===================================
OPTIONS=h
LONGOPTS=help

handle_args() {
  # Handle option args
  while true; do
      case "$1" in
          -h|--help)
              show_help
              exit 0
              ;;
          --)
              shift
              break
              ;;
          *)
              echo "Unknown options provided: $@"
              exit 51
              ;;
      esac
  done

  if [[ "$#" -eq 0 ]]; then
    show_help
    exit 0
  fi

  operation="$1"
  shift

  # Handle positional args
  case "$operation" in
    fund-collateral)
      amount_to_send="$1"
      shift
      ;;
    lock)
      amount_to_send="$1"
      shift
      ;;
    redeem)
      ;;
    clean-tx-log)
      ;;
    *)
      echo "Unknown operation: $@"
      exit 52
      ;;
  esac

  if [[ "$#" > 0 ]]; then
    echo "Unknown arguments provided for operation '$operation': '$@'"
    exit 53
  fi
}

show_help() {
  # Help message
  echo "$(basename "$0") - example script that implements Exercise 3"
  echo "for the Alonzo Testnet. Exercise 3 locks and then redeems"
  echo "some funds into/from a script that always succeeds."
  echo ""
  echo "Usage: $(basename "$0") [OPTIONS] OPERATION WALLET_ID"
  echo ""
  echo "Available options:"
  echo "  -h, --help                     display this help message"
  echo ""
  echo "Operations:"
  echo "  fund-collateral AMOUNT         send AMOUNT to collateral wallet"
  echo "  lock AMOUNT                    lock AMOUNT of funds into the script"
  echo "  redeem                         redeem funds from the script"
  echo "  clean-tx-log                   remove previous unsubmitted transactions"
}

# ======================================================================
# Let's go!
# ===================================

# Test whether getopt works
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
  echoerr "'getopt --test' failed"
  exit 101
fi

# Parse command-line arguments, canonicalizing in-place
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  echoerr "Failed to parse arguments"
  exit 102
fi

# Handle arguments
eval handle_args "$PARSED"

# Perform the main program
main

