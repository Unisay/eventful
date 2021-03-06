module Bank.CLI.Store
  ( runDB
  , cliEventStore
  , cliGloballyOrderedEventStore
  , printJSONPretty
  ) where

import Control.Monad.IO.Class (MonadIO (..))
import Data.Aeson
import Data.Aeson.Encode.Pretty
import qualified Data.ByteString.Lazy.Char8 as BSL
import Database.Persist.Sqlite

import Eventful
import Eventful.Store.Sqlite

import Bank.Models
import Bank.ProcessManagers.TransferManager

runDB :: ConnectionPool -> SqlPersistT IO a -> IO a
runDB = flip runSqlPool

cliEventStore :: (MonadIO m) => EventStore BankEvent (SqlPersistT m)
cliEventStore = synchronousEventBusWrapper store handlers
  where
    sqlStore = sqliteEventStore defaultSqlEventStoreConfig
    store = serializedEventStore jsonStringSerializer sqlStore
    handlers =
      [ eventPrinter
      , transferManagerHandler
      ]

cliGloballyOrderedEventStore :: (MonadIO m) => GloballyOrderedEventStore BankEvent (SqlPersistT m)
cliGloballyOrderedEventStore =
  serializedGloballyOrderedEventStore jsonStringSerializer
    (sqlGloballyOrderedEventStore defaultSqlEventStoreConfig)

type BankEventHandler m = EventStore BankEvent (SqlPersistT m) -> UUID -> BankEvent -> SqlPersistT m ()

eventPrinter :: (MonadIO m) => BankEventHandler m
eventPrinter _ uuid event = liftIO $ printJSONPretty (uuid, event)

transferManagerHandler :: (MonadIO m) => BankEventHandler m
transferManagerHandler store _ _ = do
  let projection = processManagerProjection transferProcessManager
  (transferState, _) <- getLatestGlobalProjection cliGloballyOrderedEventStore projection Nothing
  applyProcessManagerCommandsAndEvents transferProcessManager store transferState

printJSONPretty :: (ToJSON a) => a -> IO ()
printJSONPretty = BSL.putStrLn . encodePretty' (defConfig { confIndent = Spaces 2 })
