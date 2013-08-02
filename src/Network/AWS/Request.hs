{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TemplateHaskell            #-}

-- |
-- Module      : Network.AWS.Request
-- Copyright   : (c) 2013 Brendan Hay <brendan.g.hay@gmail.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan.g.hay@gmail.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)

module Network.AWS.Request where

import           Control.Applicative
import           Control.Exception
import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Data.ByteString        (ByteString)
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Char8  as BS
import qualified Data.ByteString.Lazy   as LBS
import           Data.Data
import qualified Data.Digest.Pure.SHA   as SHA
import           Data.List
import           Data.Map               (Map)
import           Data.Maybe
import           Data.Monoid
import           Data.Time              (UTCTime, formatTime, getCurrentTime)
import           Network.AWS.Types
import qualified Network.HTTP.Types     as HTTP
import           Network.Http.Client
import           System.Environment
import           System.IO.Streams      (InputStream)
import qualified System.IO.Streams      as Streams
import           System.Locale          (defaultTimeLocale, iso8601DateFormat)
import           Text.Hastache
import           Text.Hastache.Context

runAWS :: AWS a -> IO a
runAWS aws = do
    creds <- maybe env return Nothing
    putStrLn $ "Found: " ++ show creds
    runReaderT (unWrap aws) creds
  where
    env = do
        (acc, sec) <- (,)
            <$> lookupEnv "ACCESS_KEY_ID"
            <*> lookupEnv "SECRET_ACCESS_KEY"
        return . fromMaybe (error "Oh noes!") $
            Credentials <$> fmap BS.pack acc <*> fmap BS.pack sec
    -- metadataCredentials

send :: AWSRequest a => a -> AWS ()
send rq = do
    SignedRequest{..} <- request rq
    liftIO . bracket (establishConnection rqUrl) closeConnection $ \conn -> do
        sendRequest conn rqRequest $ inputStreamBody rqStream
        receiveResponse conn (\p i -> do
            x <- Streams.read i
            BS.putStr $ fromMaybe "" x)

sign :: SigningVersion -> RawRequest a -> AWS SignedRequest
sign Version2 = version2
sign Version3 = version3

version2 :: RawRequest a -> AWS SignedRequest
version2 RawRequest{..} = do
    Credentials{..} <- ask
    time            <- liftIO getCurrentTime

    let act = fromMaybe (error "Handle missing action") rqAction
        qry = query act accessKey time
        sig = signature secretKey act qry
        url = "https://"
            <> rqHost
            <> "/"
            <> rqPath
            <> "?"
            <> qry
            <> "&Signature="
            <> sig

    liftIO $ SignedRequest url
        <$> buildRequest (http rqMethod url)
        <*> templateStream rqBody
  where
    query action access time = queryString $ rqQuery `union`
        [ ("Action",           action)
        , ("Version",          apiVersion)
        , ("SignatureVersion", "2")
        , ("SignatureMethod",  "HmacSHA256")
        , ("Timestamp",        timeFormat time)
        , ("AWSAccessKeyId",   access)
        ]

    signature secret action qry = HTTP.urlEncode True
        . Base64.encode
        . LBS.toStrict
        . SHA.bytestringDigest
        . SHA.hmacSha256 (LBS.fromStrict secret)
        . LBS.fromStrict
        $ BS.intercalate "\n"
            [ packMethod rqMethod
            , rqHost
            , action
            , qry
            ]

version3 :: RawRequest a -> AWS SignedRequest
version3 RawRequest{..} = do
    Credentials{..} <- ask
    time            <- liftIO getCurrentTime

    let meth = packMethod rqMethod
        sig  = signature secretKey time
        auth = authorization accessKey sig
        url  = "https://"
            <> rqHost
            <> "/"
            <> apiVersion
            <> "/"
            <> rqPath
            <> "?"
            <> query accessKey

    liftIO . buildRequest $ do
        http meth url
        setHeader "X-Amzn-Authorization" auth
  where
    query access = queryString $ ("AWSAccessKeyId", access) : rqQuery

    authorization access sig = "AWS3-HTTPS AWSAccessKeyId="
        <> access
        <> ",Algorithm=HmacSHA256,Signature="
        <> sig

    signature secret = Base64.encode
        . LBS.toStrict
        . SHA.bytestringDigest
        . SHA.hmacSha256 (LBS.fromStrict secret)
        . LBS.fromStrict
        . timeFormat

apiVersion :: ByteString
apiVersion = "2012-12-01"

packMethod :: Method -> ByteString
packMethod = BS.pack . show

queryString :: [(ByteString, ByteString)] -> ByteString
queryString = BS.intercalate "&" . map concatEq . sort
  where
    concatEq (k, v) = mconcat [k, "=", HTTP.urlEncode True v]

timeFormat :: UTCTime -> ByteString
timeFormat = BS.pack . formatTime defaultTimeLocale fmt
  where
    fmt = iso8601DateFormat $ Just "%XZ"

templateStream :: AWSTemplate a => a -> IO (InputStream ByteString)
templateStream tmpl = Streams.fromByteString
    <$> hastacheStr defaultConfig (template tmpl) (mkGenericContext tmpl)
