{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}

-- Module      : Network.AWS.Data.Body
-- Copyright   : (c) 2013-2014 Brendan Hay <brendan.g.hay@gmail.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan.g.hay@gmail.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)

module Network.AWS.Data.Body where
    -- (
    -- -- * Types
    --   BodySource (..)
    -- , Body
    -- , clientBody
    -- , payloadHash

    -- -- * Classes
    -- , ToBody (..)
    -- ) where

import qualified Crypto.Hash.SHA256           as SHA256
import           Data.Aeson
import           Data.ByteString              (ByteString)
import qualified Data.ByteString.Base16       as Base16
import qualified Data.ByteString.Lazy         as LBS
import qualified Data.ByteString.Lazy.Char8   as LBS8
import           Data.Int
import           Data.Monoid
import           Data.String
import           Network.HTTP.Client

clientBody :: Body -> RequestBody
clientBody (BodyLBS    _ lbs) = RequestBodyLBS lbs
clientBody (BodyStream _ n p) = RequestBodyStream n p

payloadHash :: Body -> ByteString
payloadHash (BodyLBS    h _)   = h
payloadHash (BodyStream h _ _) = h

-- FIXME: need to clean this up and differentiate between rq and rs bodies
-- Think about using http-client directly - no monadresource and only with idioms
-- Would need a differentiated send function with yields the body for streaming requests?

-- data BodySource where
--     Body :: MonadResource m => ResumableSource m ByteString -> BodySource

-- instance Show BodySource where
--     show = const "MonadResource m => ResumableSource m ByteString"

data Body
    = BodyLBS    ByteString LBS.ByteString
    | BodyStream ByteString !Int64 (GivesPopper ())

instance Monoid Body where
    mempty = BodyLBS (hash "") ""

    mappend (BodyLBS _ a) (BodyLBS _ b) = let c = a <> b in BodyLBS (hash c) c
    mappend _ b                         = b

instance Show Body where
    show (BodyLBS    h lbs) = "BodyLBS "    ++ show h ++ " " ++ show lbs
    show (BodyStream h n _) = "BodyStream " ++ show h ++ " " ++ show n ++ " ..."

instance IsString Body where
    fromString = toBody . LBS8.pack

class ToBody a where
    toBody :: a -> Body
    toBody = const mempty

instance ToBody LBS.ByteString where
    toBody lbs = BodyLBS (hash lbs) lbs

instance ToBody ByteString where
    toBody = toBody . LBS.fromStrict

instance ToBody Value where
    toBody = toBody . encode

hash :: LBS8.ByteString -> ByteString
hash = Base16.encode . SHA256.hashlazy
