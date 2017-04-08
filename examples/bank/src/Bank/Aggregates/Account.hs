module Bank.Aggregates.Account
  ( Account (..)
  , AccountEvent (..)
  , AccountOpened (..)
  , AccountCredited (..)
  , AccountDebited (..)
  , AccountProjection
  , accountProjection
  , AccountCommand (..)
  , OpenAccountData (..)
  , CreditAccountData (..)
  , DebitAccountData (..)
  , AccountCommandError (..)
  , NotEnoughFundsData (..)
  , AccountAggregate
  , accountAggregate
  ) where

import Data.Aeson.TH
import GHC.Generics

import Eventful

import Bank.Events
import Bank.Json

data Account =
  Account
  { accountBalance :: Double
  , accountOwner :: Maybe String
  } deriving (Show, Eq)

deriveJSON (unPrefixLower "account") ''Account

data AccountEvent
  = AccountOpened' AccountOpened
  | AccountCredited' AccountCredited
  | AccountDebited' AccountDebited
  deriving (Show, Eq, Generic)

instance EventSumType AccountEvent

applyAccountEvent :: Account -> AccountEvent -> Account
applyAccountEvent account (AccountOpened' (AccountOpened name amount)) =
  account { accountOwner = Just name, accountBalance = amount }
applyAccountEvent account (AccountCredited' (AccountCredited amount _)) =
  account { accountBalance = accountBalance account + amount }
applyAccountEvent account (AccountDebited' (AccountDebited amount _)) =
  account { accountBalance = accountBalance account - amount }

type AccountProjection = Projection Account AccountEvent

accountProjection :: AccountProjection
accountProjection =
  Projection
  (Account 0 Nothing)
  applyAccountEvent

data AccountCommand
  = OpenAccount OpenAccountData
  | CreditAccount CreditAccountData
  | DebitAccount DebitAccountData
  deriving (Show, Eq)

data OpenAccountData =
  OpenAccountData
  { openAccountDataOwner :: String
  , openAccountDataInitialFunding :: Double
  } deriving (Show, Eq)

data CreditAccountData =
  CreditAccountData
  { creditAccountDataAmount :: Double
  , creditAccountDataReason :: String
  } deriving (Show, Eq)

data DebitAccountData =
  DebitAccountData
  { debitAccountDataAmount :: Double
  , debitAccountDataReason :: String
  } deriving (Show, Eq)

data AccountCommandError
  = AccountAlreadyOpenError
  | InvalidInitialDepositError
  | NotEnoughFundsError NotEnoughFundsData
  deriving (Show, Eq)

data NotEnoughFundsData =
  NotEnoughFundsData
  { notEnoughFundsDataRemainingFunds :: Double
  } deriving  (Show, Eq)

deriveJSON (unPrefixLower "notEnoughFundsData") ''NotEnoughFundsData
deriveJSON defaultOptions ''AccountCommandError

applyAccountCommand :: Account -> AccountCommand -> Either AccountCommandError [AccountEvent]
applyAccountCommand account (OpenAccount (OpenAccountData owner amount)) =
  case accountOwner account of
    Just _ -> Left AccountAlreadyOpenError
    Nothing ->
      if amount < 0
      then Left InvalidInitialDepositError
      else Right [AccountOpened' $ AccountOpened owner amount]
applyAccountCommand _ (CreditAccount (CreditAccountData amount reason)) =
  Right [AccountCredited' $ AccountCredited amount reason]
applyAccountCommand account (DebitAccount (DebitAccountData amount reason)) =
  if accountBalance account - amount < 0
  then Left $ NotEnoughFundsError (NotEnoughFundsData $ accountBalance account)
  else Right [AccountDebited' $ AccountDebited amount reason]

type AccountAggregate = Aggregate Account AccountEvent AccountCommand AccountCommandError

accountAggregate :: AccountAggregate
accountAggregate = Aggregate applyAccountCommand accountProjection