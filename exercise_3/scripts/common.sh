#!/bin/bash

# ======================================================================
# Common prelude
# ===================================
common() {
  # ===================================
  # Script and datum
  script_file="./plutus/untyped-always-succeeds-txin.plutus"
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
  # Locking cost
  locking_fee=$((250*1000))
  echo Locking fee: $locking_fee

  # ===================================
  # Redemption cost
  fixed_cost=$((1000*1000))
  echo Fixed cost: $fixed_cost

  min_execution_units=$(cat $script_budget_file | jq)

  min_execution_cost=$(jq -n -r \
    --argjson fixed_cost $fixed_cost \
    --argjson prices "$(cardano-cli query protocol-parameters --testnet-magic 5 | jq '.executionUnitPrices')" \
    --argjson budget "$min_execution_units" \
    '{"Steps": ($prices.priceSteps * $budget.Steps), "Memory": ($prices.priceMemory * $budget.Memory)} | add')

  min_redemption_cost=$(($min_execution_cost + $fixed_cost))
  echo Minimum Cost to Redeem: $min_redemption_cost

  scalar_factor=20
  scaled_execution_units=$(echo $min_execution_units | jq --argjson factor $scalar_factor 'map_values(. * $factor)')
  scaled_execution_cost=$(($min_redemption_cost * $scalar_factor))
  scaled_redemption_cost=$(($scaled_execution_cost + $fixed_cost))
  echo "Scalar factor: $scalar_factor"
  echo "Scaled-up Execution Units to Redeem (just in case): $scaled_execution_units"
  echo "Scaled-up Cost to Redeem (just in case): $scaled_redemption_cost"

  execution_units="($(echo $scaled_execution_units | jq -r 'join (", ")'))"
  echo Execution Units: $execution_units

  # ===================================
  # Required collateral
  collateral_percentage=$(cardano-cli query protocol-parameters --testnet-magic 5 | jq -r '.collateralPercentage')
  collateral_value_required=$(($scaled_redemption_cost * $collateral_percentage / 100))
  echo Collateral Percentage Required: $collateral_percentage%
  echo Collateral Value Required: $collateral_value_required
}

# ======================================================================
# Log generated and submitted transactions
# ===================================
clean_tx_log() {
  cd "./tx"
  transactions=$(ls \
    | jq -R \
    | jq --slurp 'map(capture("(?<name>.+)\\.(?<ext>\\w+)$")) | group_by(.name)' \
    | jq 'map(select(map(.ext) | contains(["submitted"]) | not))' \
    | jq 'flatten | map("\(.name).\(.ext)") | join (" ")' \
    | jq -r)
  if [ ! -z "$transactions" ]; then
    rm --verbose $transactions
  fi
}

setup_tx_file() {
  tx_name="transaction_$(date +'%Y-%m-%d_%T')_$operation"

  tx_file="./tx/$tx_name"
}

# ======================================================================
# Transaction expiry slot
# ===================================
get_tx_expiry_slot() {
  if [ "$#" -eq 0 ]; then
    echo "Missing address argument to 'tx_expiry_slot/1'"
    exit 1
  fi

  current_slot=$(cardano-cli query tip --testnet-magic 5 | jq '.slot')

  tx_expiry_slot=$(($current_slot + "$1"))
}

# ======================================================================
# Submit transaction
# ===================================
submit() {
  if [ -f $tx_file.signed ]; then
    read -p "Are you sure you want to submit this transaction (y/n)? " -n 1 -r approve_submit
    echo ""
    if [[ $approve_submit =~ ^[Yy]$ ]]; then
      touch $tx_file.submitted
      cardano-cli transaction submit --testnet-magic 5 --tx-file $tx_file.signed
    fi
  fi
}

# ======================================================================
# Balance: utxos at address
# ===================================
balance() {
  if [ "$#" -eq 0 ]; then
    echo "Missing address argument to 'balance/1'"
    exit 1
  fi
  cardano-cli query utxo --testnet-magic 5 --address "$1" --out-file /dev/stdout
}

