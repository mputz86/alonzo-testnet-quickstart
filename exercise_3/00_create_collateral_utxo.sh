#!/bin/bash

tx_name="$(date +'%Y-%m-%d_%T')_$(basename $0 .sh)"
echo Tx Name: $tx_name

if [ "$#" -eq 0 ]; then
  echo "Error: How much do you want to send?"
  exit 1
fi

amount_to_send="$1"
echo Amount to Send: $amount_to_send

input_balance=$(cardano-wallet balance main | jq -r --slurp 'map(to_entries | .[] | .value.value.lovelace) | add')
echo Input Balance: $input_balance

fee=$((200*1000))
echo Fee: $fee

amount_change=$(($input_balance - $fee - $amount_to_send))
echo Amount Change: $amount_change

if (( "$amount_change" < "0" )); then
  echo "Error: Input Balance ($input_balance) is insufficient to pay Amount to Send ($amount_to_send)"
  exit 1
fi

tx_in=$(cardano-wallet balance main | jq -r --slurp 'map(to_entries | .[] | .key) | join(" ")')
echo Tx In: $tx_in

tx_in_witness=$(cardano-wallet signing-key main)

tx_out_change="$(cardano-wallet main)+$amount_change"
echo Tx Out Change: $tx_out_change

tx_out_payment="$(cardano-wallet collateral)+$amount_to_send"
echo Tx Out Payment: $tx_out_payment

cardano-cli transaction build-raw --mary-era \
  --out-file tx/$tx_name.unsigned \
  --fee $fee \
  --tx-in $tx_in \
  --tx-out $tx_out_change \
  --tx-out $tx_out_payment

if [ -f tx/$tx_name.unsigned ]; then
  cardano-cli transaction sign --testnet-magic 5 \
    --out-file tx/$tx_name.signed \
    --tx-body-file tx/$tx_name.unsigned \
    --signing-key-file $tx_in_witness
fi

if [ -f tx/$tx_name.signed ]; then
  cardano-cli transaction view --tx-file tx/$tx_name.signed | yq > /dev/stdout
  read -p "Are you sure you want to submit this transaction (y/n)? " -n 1 -r confirmation
  echo ""
  if [[ $confirmation =~ ^[Yy]$ ]]; then
    touch tx/$tx_name.submitted
    cardano-cli transaction submit --testnet-magic 5 --tx-file tx/$tx_name.signed
  fi
fi

