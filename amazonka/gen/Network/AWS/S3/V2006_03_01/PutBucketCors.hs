{-# LANGUAGE DeriveGeneric               #-}
{-# LANGUAGE FlexibleInstances           #-}
{-# LANGUAGE OverloadedStrings           #-}
{-# LANGUAGE RecordWildCards             #-}
{-# LANGUAGE TypeFamilies                #-}

{-# OPTIONS_GHC -fno-warn-unused-imports #-}

-- Module      : Network.AWS.S3.V2006_03_01.PutBucketCors
-- Copyright   : (c) 2013-2014 Brendan Hay <brendan.g.hay@gmail.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan.g.hay@gmail.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)

-- | Sets the cors configuration for a bucket.
module Network.AWS.S3.V2006_03_01.PutBucketCors where

import           Control.Applicative
import           Data.ByteString      (ByteString)
import           Data.Default
import           Data.HashMap.Strict  (HashMap)
import           Data.Maybe
import           Data.Monoid
import           Data.Text            (Text)
import qualified Data.Text            as Text
import           GHC.Generics
import           Network.AWS.Data
import           Network.AWS.Response
import           Network.AWS.Types    hiding (Error)
import           Network.AWS.Request.RestS3
import           Network.AWS.S3.V2006_03_01.Types
import           Network.HTTP.Client  (RequestBody, Response)
import           Prelude              hiding (head)

-- | Default PutBucketCors request.
putBucketCors :: BucketName -- ^ '_pbcrBucket'
              -> CORSConfiguration -- ^ '_pbcrCORSConfiguration'
              -> PutBucketCors
putBucketCors p1 p2 = PutBucketCors
    { _pbcrBucket = p1
    , _pbcrCORSConfiguration = p2
    , _pbcrContentMD5 = Nothing
    }

data PutBucketCors = PutBucketCors
    { _pbcrBucket :: BucketName
    , _pbcrCORSConfiguration :: CORSConfiguration
    , _pbcrContentMD5 :: Maybe Text
    } deriving (Generic)

instance ToPath PutBucketCors where
    toPath PutBucketCors{..} = mconcat
        [ "/"
        , toBS _pbcrBucket
        ]

instance ToQuery PutBucketCors

instance ToHeaders PutBucketCors where
    toHeaders PutBucketCors{..} = concat
        [ "Content-MD5" =: _pbcrContentMD5
        ]

instance ToBody PutBucketCors where
    toBody = toBody . encodeXML . _pbcrCORSConfiguration

instance AWSRequest PutBucketCors where
    type Sv PutBucketCors = S3
    type Rs PutBucketCors = PutBucketCorsResponse

    request = put

    response _ = headerResponse . const $ Right PutBucketCorsResponse

data PutBucketCorsResponse = PutBucketCorsResponse
    deriving (Eq, Show, Generic)
