{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DefaultSignatures    #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE KindSignatures       #-}
{-# LANGUAGE OverlappingInstances #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TupleSections        #-}
{-# LANGUAGE TypeOperators        #-}

-- Module      : Network.AWS.Internal.HTTP
-- Copyright   : (c) 2013 Brendan Hay <brendan.g.hay@gmail.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan.g.hay@gmail.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)

module Network.AWS.Internal.HTTP where

import           Crypto.Hash.MD5
import           Data.ByteString        (ByteString)
import qualified Data.ByteString.Base64 as Base64
import           Data.Monoid
import           Data.Text              (Text)
import qualified Data.Text              as Text
import qualified Data.Text.Encoding     as Text
import           Data.Time
import           GHC.Generics
import           GHC.TypeLits

class IsHeader a where
    encodeHeader :: a -> Text -> (Text, Text)

instance IsHeader v => IsHeader (Text, v) where
    encodeHeader (k, v) = encodeHeader v . (`mappend` k)

instance IsHeader v => IsHeader (ByteString, v) where
    encodeHeader (k, v) = encodeHeader (Text.decodeUtf8 k, v)

instance IsHeader Text where
    encodeHeader s = (, s)

instance IsHeader ByteString where
    encodeHeader s = (, Text.decodeUtf8 s)

instance IsHeader String where
    encodeHeader s = (, Text.pack s)

instance IsHeader Integer where
    encodeHeader n = encodeHeader (show n)

data Header (k :: Symbol) v = Header v

instance Functor (Header k) where
    fmap f (Header x) = Header $ f x

instance (SingI k, IsHeader v) => IsHeader (Header k v) where
    encodeHeader h@(Header v) = encodeHeader v . mappend (withSing $ f h)
      where
        f :: Header k v -> Sing k -> Text
        f _ = Text.pack . fromSing

instance (SingI k, IsHeader v) => Show (Header k v) where
    show = show . (`encodeHeader` mempty)

data AnyHeader where
    AnyHeader :: IsHeader a => a -> AnyHeader

instance IsHeader AnyHeader where
    encodeHeader (AnyHeader h) = encodeHeader h

instance Show AnyHeader where
    show (AnyHeader h) = show $ encodeHeader h mempty

hdr :: IsHeader a => a -> AnyHeader
hdr = AnyHeader

type ContentLength     = Header "Content-Length" Integer
type ContentLanguage   = Header "Content-Language" Text
type Expect            = Header "Expect" Text
type Expires           = Header "Expires" Text
type Range             = Header "Range" Text
type IfModifiedSince   = Header "If-Modified-Since" Text
type IfUnmodifiedSince = Header "If-Unmodified-Since" Text
type IfMatch           = Header "If-Match" Text
type IfNoneMatch       = Header "If-None-Match" Text

data Content (t :: Symbol) (s :: Symbol) = Content

instance (SingI t, SingI s) => IsHeader (Content t s) where
    encodeHeader c = encodeHeader ("Content-Type" :: Text, val)
      where
        val = Text.concat [contentType c, "/", contentSubType c]

contentType :: SingI t => Content t s -> Text
contentType = withSing . f
  where
    f :: Content t s -> Sing t -> Text
    f _ = Text.pack . fromSing

contentSubType :: SingI s => Content t s -> Text
contentSubType = withSing . f
  where
    f :: Content t s -> Sing s -> Text
    f _ = Text.pack . fromSing

type JSON           = Content "application" "json"
type XML            = Content "application" "xml"
type FormURLEncoded = Content "application" "x-www-form-urlencoded"

class CacheValue a where
    cacheValue :: Text -> a -> Text

newtype Cache (k :: Symbol) v = Cache v

instance (SingI k, CacheValue v) => IsHeader (Cache k v) where
    encodeHeader c@(Cache v) =
        encodeHeader ("Cache-Control" :: Text, cacheValue (withSing $ f c) v)
      where
        f :: Cache k v -> Sing k -> Text
        f _ = Text.pack . fromSing

type Public          = Cache "public" ()
type Private         = Cache "private" (Maybe Text)
type NoCache         = Cache "no-cache" (Maybe Text)
type NoStore         = Cache "no-store" ()
type NoTransform     = Cache "no-transform" ()
type MustRevalidate  = Cache "must-revalidate" ()
type ProxyRevalidate = Cache "proxy-revalidate" ()
type MaxAge          = Cache "max-age" Integer
type SMaxAge         = Cache "s-maxage" Integer
type MaxStale        = Cache "max-stale" (Maybe Integer)
type MinFresh        = Cache "min-fresh" Integer
type OnlyIfCache     = Cache "only-if-cached" ()

data Encoding (t :: Symbol) = Encoding

instance SingI t => IsHeader (Encoding t) where
    encodeHeader e = encodeHeader ("Encoding" :: Text, withSing $ f e)
      where
        f :: Encoding t -> Sing t -> Text
        f _ = Text.pack . fromSing

type GZip    = Encoding "gzip"
type Deflate = Encoding "deflate"

newtype Param (k :: Symbol) v = Param v

class ParamValue a where
    paramValue :: a -> Text

instance ParamValue Text where
    paramValue = id

instance (SingI k, ParamValue v) => ParamValue (Param k v) where
    paramValue p@(Param v) = Text.concat [withSing $ f p, "=", paramValue v]
      where
        f :: Param k v -> Sing k -> Text
        f _ = Text.pack . fromSing

data AnyParam where
    AnyParam :: ParamValue a => a -> AnyParam

instance ParamValue AnyParam where
    paramValue (AnyParam p) = paramValue p

prm :: ParamValue a => a -> AnyParam
prm = AnyParam

newtype Disposition (t :: Symbol) = Disposition [AnyParam]

instance SingI t => IsHeader (Disposition t) where
    encodeHeader d@(Disposition ps) =
        encodeHeader ("Content-Disposition" :: Text, val)
      where
        val = Text.intercalate ";" $ withSing (f d) : map paramValue ps

        f :: Disposition t -> Sing t -> Text
        f _ = Text.pack . fromSing

-- | Displayed automatically [RFC2183]
type Inline = Disposition "inline"

-- | Attachment user controlled display [RFC2183]
type Attachment = Disposition "attachment"

-- | Process as form response [RFC2388]
type FormData = Disposition "form-data"

-- | Tunneled content to be processed silently [RFC3204]
type Signal = Disposition "signal"

-- | Custom ring tone to alert the user [RFC3261]
type Alert = Disposition "alert"

-- | Displayed as an icon to the user [RFC3261]
type Icon = Disposition "icon"

-- | Should be displayed to the user [RFC3261]
type Render = Disposition "render"

-- | Contains a list of URIs that indicates the recipients
-- of the request [RFC5364]
type RecipientListHistory = Disposition "recipient-list-history"

-- | Describes a communications session.
-- For example, an RFC2327 SDP body [RFC3261]
type Session = Disposition "session"

-- | Authenticated Identity Body [RFC3893]
type AIB = Disposition "aib"

-- | Describes an early communications session.
-- For example, and [RFC2327] SDP body [RFC3959]
type EarlySession = Disposition "early-session"

-- | Includes a list of URIs to which URI-list services
-- are to be applied. [RFC5363]
type RecipientList = Disposition "recipient-list"

-- | Payload of the message carrying this Content-Disposition header
-- field value is an Instant Message Disposition Notification as requested
-- in the corresponding Instant Message. [RFC5438]
type Notification = Disposition "notification"

-- | Needs to be handled according to a reference to the body that is located
-- in the same SIP message as the body. [RFC5621]
type ByReference = Disposition "by-reference"

-- | Contains information associated with an Info Package
type InfoPackage = Disposition "info-package"

-- | Name to be used when creating file [RFC2183]
type FileName = Param "filename" Text

-- | When content was created [RFC2183]
type CreationDate = Param "creation-date" UTCTime

-- | When content was last modified [RFC2183]
type ModificationDate = Param "modification-date" UTCTime

-- | When content was last read [RFC2183]
type ReadDate = Param "read-date" UTCTime

-- | Approximate size of content in octets [RFC2183]
type Size = Param "size" Integer

-- | Original field name in form [RFC2388]
type Name = Param "name" Text

-- | Whether or not processing is required [RFC3204]
type Handling = Param "handling" HandlingType

-- | Type or use of audio content [RFC2421]
type Voice = Param "voice" VoiceType

data HandlingType
    = Required
    | Optional
      deriving (Eq, Show)

instance ParamValue HandlingType where
    paramValue Required = "required"
    paramValue Optional = "optional"

data VoiceType
    = VoiceMessage
    | VoiceMessageNotification
    | OriginatorSpokenName
    | RecipientSpokenName
    | SpokenSubject
      deriving (Eq, Show)

instance ParamValue VoiceType where
    paramValue vt = case vt of
        VoiceMessage             -> "Voice-Message"
        VoiceMessageNotification -> "Voice-Message-Notification"
        OriginatorSpokenName     -> "Originator-Spoken-Name"
        RecipientSpokenName      -> "Recipient-Spoken-Name"
        SpokenSubject            -> "Spoken-Subject"

newtype MD5 = MD5 ByteString deriving (Eq, Show)

md5 :: ByteString -> MD5
md5 = MD5 . Base64.encode . hash

instance IsHeader MD5 where
    encodeHeader (MD5 bs) =
        encodeHeader ("Content-MD5" :: Text, Text.decodeUtf8 bs)

--
-- Generics
--

-- | Supplementary class to extract any header types from a record,
-- ignoring everything else.
class ToHeaders a where
    toHeaders :: a -> [AnyHeader]

    default toHeaders :: (Generic a, GHeaders (Rep a)) => a -> [AnyHeader]
    toHeaders = genericHeaders

genericHeaders :: (Generic a, GHeaders (Rep a)) => a -> [AnyHeader]
genericHeaders f = gHeaders (from f)

class GHeaders f where
    gHeaders :: f a -> [AnyHeader]

instance GHeaders (K1 i a) where
    gHeaders _ = []

instance GHeaders a => GHeaders (M1 i c a) where
    gHeaders = gHeaders . unM1

instance (Selector s, SingI k, IsHeader v) => GHeaders (S1 s (K1 i (Header k v))) where
    gHeaders = (:[]) . hdr . unK1 . unM1

instance Selector s => GHeaders (S1 s (K1 i [AnyHeader])) where
    gHeaders = unK1 . unM1

instance (GHeaders f, GHeaders g) => GHeaders (f :*: g) where
    gHeaders (f :*: g) = gHeaders f <> gHeaders g
