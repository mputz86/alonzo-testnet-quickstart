#!/bin/bash

tx_name="$(date +'%Y-%m-%d_%T')_$(basename $0 .sh)"
echo Tx Name: $tx_name

if [ "$#" -eq 0 ]; then
  echo "Error: How much do you want to send?"
  exit 1
fi

amount_to_send="$1"
echo Amount to Send: $amount_to_send

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

if [ $utxos_with_my_datum_len -ne 0 ]; then
  echo "Utxos detected with this datum. It's better to either redeem them first, or choose another datum."
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
# Wallet utxo selection
# ===================================
main_wallet_utxos_sufficient=$(cardano-wallet balance main | \
  jq -r --argjson payment $(($locking_fee + $amount_to_send)) \
  'to_entries | map(select(.value.value.lovelace >= $payment))')
main_wallet_utxos_sufficient_len=$(echo $main_wallet_utxos_sufficient | jq 'length')
echo Main Wallet Sufficient Utxos: $main_wallet_utxos_sufficient_len
echo $main_wallet_utxos_sufficient

# ======================================================================
# Lovelace inflow and outflow
# ===================================
echo Main Wallet: $(cardano-wallet main)

inflow=$(echo $main_wallet_utxos_sufficient | jq -r '.[0].value.value.lovelace')
echo Input Balance: $inflow

fee=$locking_fee
echo Fee: $fee

amount_change=$(($inflow - $fee - $amount_to_send))
echo Amount Change: $amount_change

if (( "$amount_change" < "0" )); then
  echo "Error: Input Balance ($inflow) is insufficient to pay Amount to Send ($amount_to_send)"
  exit 1
fi

# ======================================================================
# Inputs and outputs
# ===================================
tx_in=$(echo $main_wallet_utxos_sufficient | jq -r '.[0].key')
echo Tx In: $tx_in

tx_in_signing_key=$(cardano-wallet signing-key main)

tx_out_change="$(cardano-wallet main)+$amount_change"
echo Tx Out Change: $tx_out_change

tx_out_payment="$script_address+$amount_to_send"
echo Tx Out Payment: $tx_out_payment

# ======================================================================
# Construct transaction
# ===================================
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

