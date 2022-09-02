#!/usr/bin/env bash

# Unofficial bash strict mode.
# See: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -e
set -o pipefail
## Set up variables
export WORK="${WORK:-example/work/preview/babbage/example-bbabbage-script-usage/toy-examplev2-typed}"
export BASE="${BASE:-.}"
export CARDANO_CLI="${CARDANO_CLI:-cardano-cli}"
export TESTNET_MAGIC="${TESTNET_MAGIC:-2}"
export UTXO_VKEY="${UTXO_VKEY:-/home/jsrqv/cardano-development/preview/wallet-preview-21/payment.vkey}"
export UTXO_SKEY="${UTXO_SKEY:-/home/jsrqv/cardano-development/preview/wallet-preview-21/payment.skey}"
export RESULT_FILE="${RESULT_FILE:-$WORK/result.out}"

## plutus spending script
# plutusspendingscript="$BASE/scripts/plutus/scripts/v2/required-redeemer.plutus"
plutusspendingscript="/home/jsrqv/code/haskell/vasil-playground/oracleToy.plutus"

## Datum 42 (existing examples from cardano node)
# datumfilepath="$BASE/scripts/plutus/data/typed-42.datum"
# redeemerfilepath="$BASE/scripts/plutus/data/typed-42.redeemer"

echo "Script at: $plutusspendingscript"

## Step 1: Create a tx output with a inline datum at the script address.
## In order for a tx output to be locked by a plutus script.
## We also need collateral tx inputs so we split the utxo
## in order to accommodate this.

plutusspendingscriptaddr=$($CARDANO_CLI address build --payment-script-file "$plutusspendingscript"  --testnet-magic "$TESTNET_MAGIC")
echo "Plutus Script Address"
echo "$plutusspendingscriptaddr"

mkdir -p "$WORK"

## owner wallet address
utxoaddr=$($CARDANO_CLI address build --testnet-magic "$TESTNET_MAGIC" --payment-verification-key-file "$UTXO_VKEY")

$CARDANO_CLI query utxo --address "$utxoaddr" --cardano-mode --testnet-magic "$TESTNET_MAGIC" --out-file $WORK/utxo-1.json
cat $WORK/utxo-1.json

txin=$(jq -r 'keys[0]' $WORK/utxo-1.json)
lovelaceattxin=$(jq -r ".[\"$txin\"].value.lovelace" $WORK/utxo-1.json)
lovelaceattxindiv6=$(expr $lovelaceattxin / 6)

$CARDANO_CLI query protocol-parameters --testnet-magic "$TESTNET_MAGIC" --out-file $WORK/pparams.json
dummyaddress=addr_test1vqcufrpa9qp63llv7e8l6yzmu53yq6sym9xvck0rea37gxc9emxk5
dummyaddress2=addr_test1vz8xtn5rk8hqdazttvlp80d3f2t22ahtak7wta9suya6y2cmde2zz

## We first:
## - 1 Send ADA and an inline datum to the plutus sctipt address
## - 2 Create the reference script at the $dummyaddress and send ADA and a datum.
$CARDANO_CLI transaction build \
  --babbage-era \
  --cardano-mode \
  --testnet-magic "$TESTNET_MAGIC" \
  --change-address "$utxoaddr" \
  --tx-in "$txin" \
  --tx-out "$plutusspendingscriptaddr+$lovelaceattxindiv6" \
  --tx-out-inline-datum-value 42 \
  --tx-out "$utxoaddr+$lovelaceattxindiv6" \
  --tx-out "$dummyaddress+$lovelaceattxindiv6" \
  --tx-out-inline-datum-value 42 \
  --tx-out-reference-script-file "$plutusspendingscript" \
  --protocol-params-file "$WORK/pparams.json" \
  --out-file "$WORK/create-datum-output.body"


$CARDANO_CLI transaction sign \
  --tx-body-file $WORK/create-datum-output.body \
  --testnet-magic "$TESTNET_MAGIC" \
  --signing-key-file $UTXO_SKEY \
  --out-file $WORK/create-datum-output.tx

## SUBMIT
$CARDANO_CLI transaction submit --tx-file $WORK/create-datum-output.tx --testnet-magic "$TESTNET_MAGIC"
echo "Pausing for 120 seconds..."
sleep 2m

$CARDANO_CLI query utxo --address "$dummyaddress" --cardano-mode --testnet-magic "$TESTNET_MAGIC" --out-file $WORK/dummy-address-ref-script.json
cat $WORK/dummy-address-ref-script.json

# Get reference script txin
plutusreferencescripttxin=$(jq -r 'keys[0]' $WORK/dummy-address-ref-script.json)

## Step 2
# After "locking" the tx output at the script address,
# let's spend the utxo as the script address using the
# corresponding reference script

## Get funding inputs
$CARDANO_CLI query utxo --address "$utxoaddr" --cardano-mode --testnet-magic "$TESTNET_MAGIC" --out-file $WORK/utxo-2.json


txin1=$(jq -r 'keys[0]' $WORK/utxo-2.json)
txinCollateral=$(jq -r 'keys[1]' $WORK/utxo-2.json)
suppliedCollateral=$(jq -r ".[\"$txinCollateral\"].value.lovelace" $WORK/utxo-2.json)

# Get input at plutus script that we will attempt to spend
$CARDANO_CLI query utxo --address $plutusspendingscriptaddr --testnet-magic "$TESTNET_MAGIC" --out-file $WORK/plutusutxo.json
plutuslockedutxotxin=$(jq -r 'keys[0]' $WORK/plutusutxo.json)
lovelaceatplutusspendingscriptaddr=$(jq -r ".[\"$plutuslockedutxotxin\"].value.lovelace" $WORK/plutusutxo.json)

echo "Plutus txin"
echo "$plutuslockedutxotxin"
echo ""
echo "Collateral"
echo "$txinCollateral"
echo "$suppliedCollateral"
echo ""
echo "Funding utxo"
echo "$txin1"
echo ""
echo "Plutus reference script txin"
echo "$plutusreferencescripttxin"
echo ""
echo "Plutus input we are trying to spend"
echo "$plutuslockedutxotxin"

returncollateral=$(expr $suppliedCollateral - 529503)

echo "Return collateral amount"
echo "$returncollateral"

$CARDANO_CLI transaction build \
  --babbage-era \
  --cardano-mode \
  --testnet-magic "$TESTNET_MAGIC" \
  --change-address "$utxoaddr" \
  --tx-in "$txin1" \
  --tx-in-collateral "$txinCollateral" \
  --tx-total-collateral 529503 \
  --tx-out-return-collateral "$utxoaddr+$returncollateral" \
  --out-file "$WORK/test-babbage-ref-script.body" \
  --tx-in "$plutuslockedutxotxin" \
  --spending-tx-in-reference "$plutusreferencescripttxin" \
  --spending-plutus-script-v2 \
  --spending-reference-tx-in-inline-datum-present \
  --spending-reference-tx-in-redeemer-value 42 \
  --tx-out "$dummyaddress2+1000000" \
  --protocol-params-file "$WORK/pparams.json"

$CARDANO_CLI transaction sign \
  --tx-body-file $WORK/test-babbage-ref-script.body \
  --testnet-magic "$TESTNET_MAGIC" \
  --signing-key-file "${UTXO_SKEY}" \
  --out-file $WORK/babbage-ref-script.tx

# SUBMIT $WORK/babbage.tx
echo "Submit the tx using reference script and wait 120 seconds..."
$CARDANO_CLI transaction submit --tx-file $WORK/babbage-ref-script.tx --testnet-magic "$TESTNET_MAGIC"
sleep 2m
echo ""
echo "Querying UTxO at $dummyaddress2. If there is ADA at the address the Plutus reference script successfully executed!"
echo ""
$CARDANO_CLI query utxo --address "$dummyaddress2"  --testnet-magic "$TESTNET_MAGIC" \
  | tee "$RESULT_FILE"
