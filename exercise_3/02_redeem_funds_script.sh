#!/bin/bash

tx_name="$(date +'%Y-%m-%d_%T')_$(basename $0 .sh)"
echo Tx Name: $tx_name

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

# ======================================================================
# Script and datum
# ===================================
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

# ======================================================================
# Script utxo selection
# ===================================
utxos_with_my_datum=$(balance $(cat plutus/untyped-always-succeeds-txin.plutus.addr) --out-file /dev/stdout | \
  jq --arg utxo $datum_hash 'to_entries | map(select(.value.data == $utxo))')
utxos_with_my_datum_len=$(echo $utxos_with_my_datum | jq 'length')
echo Utxos with My Datum: $utxos_with_my_datum_len
echo $utxos_with_my_datum

if [ $utxos_with_my_datum_len -eq 0 ]; then
  echo "No utxos detected with this datum. There is nothing to redeem."
  exit 1
fi

# ======================================================================
# Locking cost
# ===================================
locking_fee=$((250*1000))
echo Locking fee: $locking_fee

# ======================================================================
# Redemption cost
# ===================================
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

# ======================================================================
# Lovelace inflow and outflow
# ===================================
echo Main Wallet: $(cardano-wallet main)

inflow=$(echo $utxos_with_my_datum | jq '.[0].value.value.lovelace')
echo Inflow: $inflow

fee=$scaled_redemption_cost
echo Fee: $fee

amount_change=$(($inflow - $fee))
echo Amount Change: $amount_change

if (( "$amount_change" < "0" )); then
  echo "Error: Input Balance ($inflow) is insufficient to pay the fee ($fee)"
  exit 1
fi

# ======================================================================
# Collateral selection
# ===================================
collateral_percentage=$(cat params.json | jq '.collateralPercentage')
collateral_value_required=$(($fee * $collateral_percentage / 100))
echo Collateral Percentage Required: $collateral_percentage%
echo Collateral Value Required: $collateral_value_required

utxos_with_sufficient_collateral=$(cardano-wallet balance collateral | \
  jq -r --argjson required $collateral_value_required 'to_entries | map(select(.value.value.lovelace >= $required))')
utxos_with_sufficient_collateral_len=$(echo $utxos_with_my_datum | jq 'length')
echo Utxos with Sufficient Collateral: $utxos_with_sufficient_collateral_len
echo $utxos_with_sufficient_collateral

if [ $utxos_with_sufficient_collateral_len -eq 0 ]; then
  echo "No utxos detected with sufficient collateral. Load the collateral wallet with more funds before proceeding."
  exit 1
fi

# ======================================================================
# Inputs and outputs
# ===================================
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

# ======================================================================
# Construct transaction
# ===================================
cardano-cli transaction build-raw --alonzo-era \
  --out-file tx/$tx_name.unsigned \
  --fee $fee \
  --protocol-params-file params.json \
  --tx-in $tx_in \
  --tx-in-script-file $script_file \
  --tx-in-datum-value $datum \
  --tx-in-redeemer-value $datum \
  --tx-in-execution-units "$execution_units" \
  --tx-in-collateral $tx_in_collateral \
  --tx-out $tx_out_change

if [ -f tx/$tx_name.unsigned ]; then
  cardano-cli transaction sign --testnet-magic 5 \
    --out-file tx/$tx_name.signed \
    --tx-body-file tx/$tx_name.unsigned \
    --signing-key-file $tx_in_collateral_signing_key
fi

# ======================================================================
# Submit
# ===================================
if [ -f tx/$tx_name.signed ]; then
  read -p "Are you sure you want to submit this transaction (y/n)? " -n 1 -r confirmation
  echo ""
  if [[ $confirmation =~ ^[Yy]$ ]]; then
    touch tx/$tx_name.submitted
    cardano-cli transaction submit --testnet-magic 5 --tx-file tx/$tx_name.signed
  fi
fi

