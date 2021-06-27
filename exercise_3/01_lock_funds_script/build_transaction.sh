#!/bin/bash

echoerr (){
  cat <<< "$@" 1>&2;
}

# input_balance=$(cardano-wallet balance 2 | jq -r --slurp 'map(to_entries | .[] | .value.value.lovelace) | add')
# echoerr Input Balance: $input_balance

# fee=$((801*1000*1000))
# echoerr Fee: $fee

# amount_to_send=$((100*1000*1000))
# echoerr Amount to Send: $amount_to_send

# amount_change=$(($input_balance - $fee - $amount_to_send))
# echoerr Amount Change: $amount_change

# tx_in=$(cardano-wallet balance 1 | jq -r --slurp 'map(to_entries | .[] | .key) | join(" ")')
# echoerr Tx In: $tx_in

# tx_in_witness=$(cardano-wallet signing-key 1)

# tx_out_change="$(cardano-wallet 1)+$amount_change"
# echoerr Tx Out Change: $tx_out_change

# tx_out_payment="$(cardano-wallet 2)+$amount_to_send"
# echoerr Tx Out Payment: $tx_out_payment

# cardano-cli transaction build-raw --mary-era \
#   --out-file tx.unsigned \
#   --fee $fee \
#   --tx-in $tx_in \
#   --tx-out $tx_out_change \
#   --tx-out $tx_out_payment \
# && \
# (cardano-cli transaction view --tx-body-file tx.unsigned | yq > tx_unsigned.json) \
# && \
# cardano-cli transaction sign --testnet-magic 5 \
#   --out-file tx.signed \
#   --tx-body-file tx.unsigned \
#   --signing-key-file $tx_in_witness \
# && \
# (cardano-cli transaction view --tx-file tx.signed | yq > tx_signed.json) \
# 1>&2
