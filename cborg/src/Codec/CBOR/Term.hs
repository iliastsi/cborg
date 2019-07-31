{-# LANGUAGE CPP          #-}
{-# LANGUAGE BangPatterns #-}

-- |
-- Module      : Codec.CBOR.Term
-- Copyright   : (c) Duncan Coutts 2015-2017
-- License     : BSD3-style (see LICENSE.txt)
--
-- Maintainer  : duncan@community.haskell.org
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--
-- This module provides an interface for decoding and encoding arbitrary
-- CBOR values (ones that, for example, may not have been generated by this
-- library).
--
-- Using 'decodeTerm', you can decode an arbitrary CBOR value given to you
-- into a 'Term', which represents a CBOR value as an AST.
--
-- Similarly, if you wanted to encode some value into a CBOR value directly,
-- you can wrap it in a 'Term' constructor and use 'encodeTerm'. This
-- would be useful, as an example, if you needed to serialise some value into
-- a CBOR term that is not compatible with that types 'Serialise' instance.
--
-- Because this interface gives you the ability to decode or encode any
-- arbitrary CBOR term, it can also be seen as an alternative interface to the
-- 'Codec.CBOR.Encoding' and
-- 'Codec.CBOR.Decoding' modules.
--
module Codec.CBOR.Term
  ( Term(..)    -- :: *
  , encodeTerm  -- :: Term -> Encoding
  , decodeTerm  -- :: Decoder Term
  ) where

#include "cbor.h"

import           Codec.CBOR.Encoding hiding (Tokens(..))
import           Codec.CBOR.Decoding

import           Data.Word
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import           Data.Monoid
import           Control.Applicative

import Prelude hiding (encodeFloat, decodeFloat)

--------------------------------------------------------------------------------
-- Types

-- | A general CBOR term, which can be used to serialise or deserialise
-- arbitrary CBOR terms for interoperability or debugging. This type is
-- essentially a direct reflection of the CBOR abstract syntax tree as a
-- Haskell data type.
--
-- The 'Term' type also comes with a 'Serialise' instance, so you can
-- easily use @'decode' :: 'Decoder' 'Term'@ to directly decode any arbitrary
-- CBOR value into Haskell with ease, and likewise with 'encode'.
--
-- @since 0.2.0.0
data Term
  = TInt     {-# UNPACK #-} !Int
  | TInteger                !Integer
  | TBytes                  !BS.ByteString
  | TBytesI                 !LBS.ByteString
  | TString                 !T.Text
  | TStringI                !LT.Text
  | TList                   ![Term]
  | TListI                  ![Term]
  | TMap                    ![(Term, Term)]
  | TMapI                   ![(Term, Term)]
  | TTagged  {-# UNPACK #-} !Word64 !Term
  | TBool                   !Bool
  | TNull
  | TSimple  {-# UNPACK #-} !Word8
  | THalf    {-# UNPACK #-} !Float
  | TFloat   {-# UNPACK #-} !Float
  | TDouble  {-# UNPACK #-} !Double
  deriving (Eq, Ord, Show, Read)

--------------------------------------------------------------------------------
-- Main API

-- | Encode an arbitrary 'Term' into an 'Encoding' for later serialization.
--
-- @since 0.2.0.0
encodeTerm :: Term -> Encoding
encodeTerm (TInt      n)  = encodeInt n
encodeTerm (TInteger  n)  = encodeInteger n
encodeTerm (TBytes   bs)  = encodeBytes bs
encodeTerm (TString  st)  = encodeString st
encodeTerm (TBytesI bss)  = encodeBytesIndef
                            <> mconcat [ encodeBytes bs
                                       | bs <- LBS.toChunks bss ]
                            <> encodeBreak
encodeTerm (TStringI sts) = encodeStringIndef
                            <> mconcat [ encodeString str
                                       | str <- LT.toChunks sts ]
                            <> encodeBreak
encodeTerm (TList    ts)  = encodeListLen (fromIntegral $ length ts)
                            <> mconcat [ encodeTerm t | t <- ts ]
encodeTerm (TListI   ts)  = encodeListLenIndef
                            <> mconcat [ encodeTerm t | t <- ts ]
                            <> encodeBreak
encodeTerm (TMap     ts)  = encodeMapLen (fromIntegral $ length ts)
                            <> mconcat [ encodeTerm t <> encodeTerm t'
                                       | (t, t') <- ts ]
encodeTerm (TMapI ts)     = encodeMapLenIndef
                            <> mconcat [ encodeTerm t <> encodeTerm t'
                                       | (t, t') <- ts ]
                            <> encodeBreak
encodeTerm (TTagged w t)  = encodeTag64 w <> encodeTerm t
encodeTerm (TBool     b)  = encodeBool b
encodeTerm  TNull         = encodeNull
encodeTerm (TSimple   w)  = encodeSimple w
encodeTerm (THalf     f)  = encodeFloat16 f
encodeTerm (TFloat    f)  = encodeFloat   f
encodeTerm (TDouble   f)  = encodeDouble  f

-- | Decode some arbitrary CBOR value into a 'Term'.
--
-- @since 0.2.0.0
decodeTerm :: Decoder s Term
decodeTerm = do
    tkty <- peekTokenType
    case tkty of
      TypeUInt   -> do w <- decodeWord
                       return $! fromWord w
                    where
                      fromWord :: Word -> Term
                      fromWord w
                        | w <= fromIntegral (maxBound :: Int)
                                    = TInt     (fromIntegral w)
                        | otherwise = TInteger (fromIntegral w)

      TypeUInt64 -> do w <- decodeWord64
                       return $! fromWord64 w
                    where
                      fromWord64 w
                        | w <= fromIntegral (maxBound :: Int)
                                    = TInt     (fromIntegral w)
                        | otherwise = TInteger (fromIntegral w)

      TypeNInt   -> do w <- decodeNegWord
                       return $! fromNegWord w
                    where
                      fromNegWord w
                        | w <= fromIntegral (maxBound :: Int)
                                    = TInt     (-1 - fromIntegral w)
                        | otherwise = TInteger (-1 - fromIntegral w)

      TypeNInt64 -> do w <- decodeNegWord64
                       return $! fromNegWord64 w
                    where
                      fromNegWord64 w
                        | w <= fromIntegral (maxBound :: Int)
                                    = TInt     (-1 - fromIntegral w)
                        | otherwise = TInteger (-1 - fromIntegral w)

      TypeInteger -> do !x <- decodeInteger
                        return (TInteger x)
      TypeFloat16 -> do !x <- decodeFloat
                        return (THalf x)
      TypeFloat32 -> do !x <- decodeFloat
                        return (TFloat x)
      TypeFloat64 -> do !x <- decodeDouble
                        return (TDouble x)

      TypeBytes        -> do !x <- decodeBytes
                             return (TBytes x)
      TypeBytesIndef   -> decodeBytesIndef >> decodeBytesIndefLen []
      TypeString       -> do !x <- decodeString
                             return (TString x)
      TypeStringIndef  -> decodeStringIndef >> decodeStringIndefLen []

      TypeListLen      -> decodeListLen      >>= flip decodeListN []
      TypeListLen64    -> decodeListLen      >>= flip decodeListN []
      TypeListLenIndef -> decodeListLenIndef >>  decodeListIndefLen []
      TypeMapLen       -> decodeMapLen       >>= flip decodeMapN []
      TypeMapLen64     -> decodeMapLen       >>= flip decodeMapN []
      TypeMapLenIndef  -> decodeMapLenIndef  >>  decodeMapIndefLen []
      TypeTag          -> do !x <- decodeTag
                             !y <- decodeTerm
                             return (TTagged (fromIntegral x) y)
      TypeTag64        -> do !x <- decodeTag64
                             !y <- decodeTerm
                             return (TTagged x y)

      TypeBool    -> do !x <- decodeBool
                        return (TBool x)
      TypeNull    -> TNull   <$  decodeNull
      TypeSimple  -> do !x <- decodeSimple
                        return (TSimple x)
      TypeBreak   -> fail "unexpected break"
      TypeInvalid -> fail "invalid token encoding"

--------------------------------------------------------------------------------
-- Internal utilities

decodeBytesIndefLen :: [BS.ByteString] -> Decoder s Term
decodeBytesIndefLen acc = do
    stop <- decodeBreakOr
    if stop then return $! TBytesI (LBS.fromChunks (reverse acc))
            else do !bs <- decodeBytes
                    decodeBytesIndefLen (bs : acc)


decodeStringIndefLen :: [T.Text] -> Decoder s Term
decodeStringIndefLen acc = do
    stop <- decodeBreakOr
    if stop then return $! TStringI (LT.fromChunks (reverse acc))
            else do !str <- decodeString
                    decodeStringIndefLen (str : acc)


decodeListN :: Word -> [Term] -> Decoder s Term
decodeListN !n acc =
    case n of
      0 -> return $! TList (reverse acc)
      _ -> do !t <- decodeTerm
              decodeListN (n-1) (t : acc)


decodeListIndefLen :: [Term] -> Decoder s Term
decodeListIndefLen acc = do
    stop <- decodeBreakOr
    if stop then return $! TListI (reverse acc)
            else do !tm <- decodeTerm
                    decodeListIndefLen (tm : acc)


decodeMapN :: Word -> [(Term, Term)] -> Decoder s Term
decodeMapN !n acc =
    case n of
      0 -> return $! TMap (reverse acc)
      _ -> do !tm   <- decodeTerm
              !tm'  <- decodeTerm
              decodeMapN (n-1) ((tm, tm') : acc)


decodeMapIndefLen :: [(Term, Term)] -> Decoder s Term
decodeMapIndefLen acc = do
    stop <- decodeBreakOr
    if stop then return $! TMapI (reverse acc)
            else do !tm  <- decodeTerm
                    !tm' <- decodeTerm
                    decodeMapIndefLen ((tm, tm') : acc)

