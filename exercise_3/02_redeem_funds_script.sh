#!/bin/bash

# ======================================================================
# Common Utilities
# ===================================
balance() {
  if [ "$#" -eq 0 ]; then
    echo "Missing address argument to 'balance/1'"
    exit 1
  fi
  cardano-cli query utxo --testnet-magic 5 --address "$1" --out-file /dev/stdout
}

common() {
  base_dir=$(dirname $0)

  params_file="$base_dir/params.json"

  # ===================================
  # Script and datum
  script_file="$base_dir/plutus/untyped-always-succeeds-txin.plutus"
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
    --argjson prices "$(cat $params_file | jq '.executionUnitPrices')" \
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
  collateral_percentage=$(cat $params_file | jq '.collateralPercentage')
  collateral_value_required=$(($scaled_redemption_cost * $collateral_percentage / 100))
  echo Collateral Percentage Required: $collateral_percentage%
  echo Collateral Value Required: $collateral_value_required
}

# ======================================================================
# Utilities
# ===================================
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

setup_tx_log() {
  tx_name="transaction_$(date +'%Y-%m-%d_%T')_$operation"

  tx_file="$base_dir/tx/$tx_name"
  echo Transaction File: $tx_name
}

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
  setup_tx_log

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

# ======================================================================
# Submit transaction
# ===================================
submit() {
  if [ -f $tx_file.signed ]; then
    read -p "Are you sure you want to submit this transaction (y/n)? " -n 1 -r confirmation
    echo ""
    if [[ $confirmation =~ ^[Yy]$ ]]; then
      touch $tx_file.submitted
      cardano-cli transaction submit --testnet-magic 5 --tx-file $tx_file.signed
    fi
  fi
}

# ======================================================================
# Main program
# ===================================
main() {
  case $operation in
    redeem)
      common && redeem_funds && submit
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

