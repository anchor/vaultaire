{-# LANGUAGE OverloadedStrings #-}

module Marquise.Contents where

import Data.Text (Text)
import Data.Int (Int64)

data SourceTag = SourceTag {
    field :: Text,
    value :: Text
}

data Source = Source {
    tags :: [SourceTag]
}

contents :: String -> Chan [SourceTag] -> IO ()
contents endpoint source_chan = 
    withContext $ \c -> withSocket c Req $ \s -> do
        connect s endpoint
        
    
