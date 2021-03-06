--
-- Data vault for metrics
--
-- Copyright © 2013-2014 Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the 3-clause BSD licence.
--

{-# LANGUAGE RankNTypes #-}

module CommandRunners
(
    runDumpDayMap,
    runRegisterOrigin
) where

import Control.Exception (throw)
import Control.Monad
import qualified Data.ByteString.Char8 as S
import Data.Map (fromAscList)
import Data.Word (Word64)
import Marquise.Client
import Pipes
import System.Log.Logger
import System.Rados.Monadic (RadosError (..), runObject, stat, writeFull)
import Vaultaire.Daemon (dayMapsFromCeph, extendedDayOID, simpleDayOID,
                         withPool)
import Vaultaire.Types


runDumpDayMap :: String -> String -> Origin -> IO ()
runDumpDayMap pool user origin =  do
    let user' = Just (S.pack user)
    let pool' = S.pack pool

    maps <- withPool user' pool' (dayMapsFromCeph origin)
    case maps of
        Left e -> error e
        Right ((_, simple), (_, extended)) -> do
            putStrLn "Simple day map:"
            print simple
            putStrLn "Extended day map:"
            print extended

runRegisterOrigin :: String -> String -> Origin -> Word64 -> Word64 -> TimeStamp -> TimeStamp -> IO ()
runRegisterOrigin pool user origin buckets step (TimeStamp begin) (TimeStamp end) = do
    let targets = [simpleDayOID origin, extendedDayOID origin]
    let user' = Just (S.pack user)
    let pool' = S.pack pool

    withPool user' pool' (forM_ targets initializeDayMap)
  where
    initializeDayMap target =
        runObject target $ do
            result <- stat
            case result of
                Left NoEntity{} -> return ()
                Left e -> throw e
                Right _ -> liftIO $ infoM "Commands.runRegisterOrigin" ("Target already in place (" ++ S.unpack target ++ ")")

            writeFull (toWire dayMap) >>= maybe (return ()) throw

    dayMap = DayMap . fromAscList $
        ((0, buckets):)[(n, buckets) | n <- [begin,begin+step..end]]
