--
-- Data vault for metrics
--
-- Copyright © 2014      Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the BSD licence.
--

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports    #-}

module Version1.JournalFile
(
    BlockName,
    BlockSize,
    parseInboundJournal,
    makeInboundJournal,
    readJournalObject,
    writeJournalObject,
    readBlockObject,
    deleteBlockObject
) where

import Blaze.ByteString.Builder
import Blaze.ByteString.Builder.Char8
import Codec.Compression.LZ4
import Control.Exception
import "mtl" Control.Monad.Error ()
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as S
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.List (foldl')
import Data.Monoid (mempty, (<>))
import Data.Serialize
import System.Rados.Monadic


--newtype BlockName = BlockName ByteString
type BlockName = ByteString
type BlockSize = Int


parseInboundJournal :: ByteString -> [(BlockName, BlockSize)]
parseInboundJournal = map f . S.lines
  where
    f l = case S.split ',' l of
            [a,b] -> case S.readInteger b of
                Just (n,_)  -> (a, fromIntegral n)
                Nothing -> die l
            _ -> die l
    die l = error $ "Failed to parse size in journal file on line:\n\t" ++ S.unpack l

makeInboundJournal :: [(BlockName, BlockSize)] -> ByteString
makeInboundJournal = toByteString . foldl' f mempty
  where
    f builder (name, size) = builder <>
                             fromByteString name <>
                             fromChar ',' <>
                             fromShow size <>
                             fromChar '\n'


writeJournalObject
    :: ByteString
    -> HashMap BlockName BlockSize
    -> Pool ()
writeJournalObject journal' blocksm = do
    a <- runAsync . runObject journal' $ writeFull z'
    r <- waitSafe a
    case r of
        Nothing     -> return ()
        Just err    -> liftIO $ throwIO err
  where
    zs = HashMap.toList blocksm
    z' = makeInboundJournal zs


readJournalObject
    :: ByteString
    -> Pool (HashMap BlockName BlockSize)
readJournalObject journal' = do
    eb' <- runObject journal' readFull    -- Pool (Either RadosError ByteString)

    case eb' of
        Left (NoEntity _ _ _)   -> return HashMap.empty
        Left err                -> liftIO $ throwIO err
        Right b'                -> return $ HashMap.fromList $ parseInboundJournal b'



readBlockObject
    :: BlockName
    -> Pool [ByteString]
readBlockObject block' = do
    ez' <- runObject block' readFull    -- Pool (Either RadosError ByteString)

    case ez' of
        Left (NoEntity _ _ _)   -> return []
        Left err                -> liftIO $ throwIO err
        Right z'                -> return $ case decompress z' of
                                                Just z -> case decode z of
                                                            Left _      -> []
                                                            Right y's   -> y's
                                                Nothing -> []

-- FIXME throw error on decode failure? No point, really.


deleteBlockObject
    :: ByteString
    -> Pool ()
deleteBlockObject block' = do
    a <- runAsync . runObject block' $ remove
    r <- waitComplete a
    case r of
        Nothing     -> return ()
        Just err    -> liftIO $ throwIO err

