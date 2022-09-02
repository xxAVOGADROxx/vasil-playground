{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module InlineDatum where

import           Cardano.Api                    (writeFileTextEnvelope)
import           Cardano.Api.Shelley            (PlutusScript (..),
                                                 PlutusScriptV2,
                                                 ScriptDataJsonSchema (ScriptDataJsonDetailedSchema),
                                                 fromPlutusData,
                                                 scriptDataToJson)

import           Data.Functor                          (void)

import qualified Plutus.V2.Ledger.Api                   as PlutusV2
import qualified Plutus.V2.Ledger.Contexts              as PlutusV2
import qualified Plutus.Script.Utils.V2.Typed.Scripts   as PSU.V2
-- import qualified Plutus.Script.Utils.V2.Scripts         as PSU.V2
import qualified PlutusTx.Builtins as BI
import           Plutus.V2.Ledger.Tx
import           Ledger


import qualified Ledger.Typed.Scripts           as Scripts
-- for address and valHash

import qualified PlutusTx
import           PlutusTx.Prelude         as P hiding  ( Semigroup (..)
                                                       ,unless
                                                       , (.)
                                                       )
import           Prelude                               ( IO
                                                       , Semigroup (..)
                                                       , Show (..)
                                                       , print
                                                       , (.)
                                                       )
import           Codec.Serialise
import qualified Data.ByteString.Lazy             as LBS
import qualified Data.ByteString.Short            as SBS
{-
   The Oracle 100 3 validator script
-}

{-# INLINEABLE mkValidator #-}
mkValidator :: Integer -> Integer -> PlutusV2.ScriptContext -> Bool
mkValidator d r _ =
    traceIfFalse "datum is not 42" (d == 42) &&
    traceIfFalse "redeemer is not 42" (r == 42)

{-
    As a typed validator
-}

data Oracling
instance PSU.V2.ValidatorTypes Oracling where
    type instance DatumType Oracling    = Integer
    type instance RedeemerType Oracling = Integer

typedValidator :: PSU.V2.TypedValidator Oracling
typedValidator =
    PSU.V2.mkTypedValidator @Oracling
    $$(PlutusTx.compile [||mkValidator||])
    $$(PlutusTx.compile [||wrap||])
    where
        wrap = PSU.V2.mkUntypedValidator

oracleToyValidator :: PSU.V2.Validator
oracleToyValidator = PSU.V2.validatorScript typedValidator

{-
    As a Script
-}

oracleToyScript :: PlutusV2.Script
oracleToyScript = PlutusV2.unValidatorScript oracleToyValidator

{-
   As a Short Byte String
-}

oracleToySBS :: SBS.ShortByteString
oracleToySBS = SBS.toShort . LBS.toStrict $ serialise oracleToyScript

{-
   As a Serialised Script
-}

oracleToySerialised :: PlutusScript PlutusScriptV2
oracleToySerialised = PlutusScriptSerialised oracleToySBS

writeOracleToyScript :: IO ()
writeOracleToyScript = void $ writeFileTextEnvelope "oracleToy.plutus" Nothing oracleToySerialised
-- myDatum = PlutusV2.Datum $ BI.mkI 42
-- myRedeemer = PlutusV2.Redeemer $ BI.mkI 42
