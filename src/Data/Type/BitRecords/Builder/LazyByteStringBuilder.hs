{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-redundant-constraints  #-}
module Data.Type.BitRecords.Builder.LazyByteStringBuilder where

import Data.Type.BitRecords.Builder.BitBuffer
import Data.FunctionBuilder
import Data.Type.BitRecords.Core
import Data.Word
import Data.Int
import Data.Bits
import Data.Kind.Extra
import Data.Proxy
import GHC.TypeLits
import Data.Monoid
import Control.Category
import Prelude hiding ((.), id)
import qualified Data.ByteString.Builder as SB
import qualified Data.ByteString.Lazy as B
import qualified Data.ByteString as SB
import Text.Printf

-- | A wrapper around a builder derived from a 'BitStringBuilderState'
data BuilderBox where
  MkBuilderBox :: !Word64 -> !SB.Builder -> BuilderBox

instance Semigroup BuilderBox where
  (MkBuilderBox !ls !lb) <> (MkBuilderBox !rs !rb) =
    MkBuilderBox (ls + rs) (lb <> rb)

instance Monoid BuilderBox where
  mempty = MkBuilderBox 0 mempty

-- | Create a 'SB.Builder' from a 'BitRecord' and store it in a 'BuilderBox'
bitBuilderBox ::
  forall (record :: BitRecord) .
  BitStringBuilderHoley (Proxy record) BuilderBox
  =>  Proxy record
  -> ToBitStringBuilder (Proxy record) BuilderBox
bitBuilderBox = toFunction . bitBuilderBoxHoley

-- | Like 'bitBuilderBox', but 'toFunction' the result and accept as an additional
-- parameter a wrapper function to wrap the final result (the 'BuilderBox') and
-- 'toFunction' the whole machiner.
wrapBitBuilderBox ::
  forall (record :: BitRecord) wrapped .
    BitStringBuilderHoley (Proxy record) wrapped
  => (BuilderBox -> wrapped)
  -> Proxy record
  -> ToBitStringBuilder (Proxy record) wrapped
wrapBitBuilderBox !f !p = toFunction (mapAccumulator f (bitBuilderBoxHoley p))

-- | Create a 'SB.Builder' from a 'BitRecord' and store it in a 'BuilderBox';
-- return a 'FunctionBuilder' monoid that does that on 'toFunction'
bitBuilderBoxHoley ::
  forall (record :: BitRecord) r .
  BitStringBuilderHoley (Proxy record) r
  =>  Proxy record
  -> FunctionBuilder BuilderBox r (ToBitStringBuilder (Proxy record) r)
bitBuilderBoxHoley !p =
  let fromBitStringBuilder !h =
        let (BitStringBuilderState !builder _ !wsize) =
              flushBitStringBuilder
              $ appBitStringBuilder h initialBitStringBuilderState
            !out = MkBuilderBox wsize builder
        in out
  in mapAccumulator fromBitStringBuilder (bitStringBuilderHoley p)

-- * Low-level interface to building 'BitRecord's and other things

newtype BitStringBuilder =
  BitStringBuilder {unBitStringBuilder :: Dual (Endo BitStringBuilderState)}
  deriving (Monoid, Semigroup)

runBitStringBuilder
  :: BitStringBuilder -> SB.Builder
runBitStringBuilder !w =
  getBitStringBuilderStateBuilder $
  flushBitStringBuilder $ appBitStringBuilder w initialBitStringBuilderState

bitStringBuilder :: (BitStringBuilderState -> BitStringBuilderState)
                 -> BitStringBuilder
bitStringBuilder = BitStringBuilder . Dual . Endo

appBitStringBuilder :: BitStringBuilder
                    -> BitStringBuilderState
                    -> BitStringBuilderState
appBitStringBuilder !w = appEndo (getDual (unBitStringBuilder w))

data BitStringBuilderState where
        BitStringBuilderState ::
          !SB.Builder -> !BitStringBuilderChunk -> !Word64 -> BitStringBuilderState

getBitStringBuilderStateBuilder
  :: BitStringBuilderState -> SB.Builder
getBitStringBuilderStateBuilder (BitStringBuilderState !builder _ _) = builder

initialBitStringBuilderState
  :: BitStringBuilderState
initialBitStringBuilderState =
  BitStringBuilderState mempty emptyBitStringBuilderChunk 0

-- | Write the partial buffer contents using any number of 'word8' The unwritten
--   parts of the bittr buffer are at the top.  If the
--
-- >     63  ...  (63-off-1)(63-off)  ...  0
-- >     ^^^^^^^^^^^^^^^^^^^
-- > Relevant bits start to the top!
--
flushBitStringBuilder
  :: BitStringBuilderState -> BitStringBuilderState
flushBitStringBuilder (BitStringBuilderState !bldr !buff !totalSize) =
  BitStringBuilderState (writeRestBytes bldr 0)
                        emptyBitStringBuilderChunk
                        totalSize'
  where !off = bitStringBuilderChunkLength buff
        !off_ = (fromIntegral off :: Word64)
        !totalSize' = totalSize + signum (off_ `rem` 8) + (off_ `div` 8)
        !part = bitStringBuilderChunkContent buff
        -- write bytes from msb to lsb until the offset is reached
        -- >  63  ...  (63-off-1)(63-off)  ...  0
        -- >  ^^^^^^^^^^^^^^^^^^^
        -- >  AAAAAAAABBBBBBBBCCC00000
        -- >  |byte A| byte B| byte C|
        writeRestBytes !bldr' !flushOffset =
          if off <= flushOffset
             then bldr'
             else let !flushOffset' = flushOffset + 8
                      !bldr'' =
                        bldr' <>
                        SB.word8 (fromIntegral
                                 ((part `unsafeShiftR`
                                   (bitStringMaxLength - flushOffset')) .&.
                                  0xFF))
                  in writeRestBytes bldr'' flushOffset'

-- | Write all the bits, in chunks, filling and writing the 'BitString'
-- in the 'BitStringBuilderState' as often as necessary.
appendBitString :: BitString -> BitStringBuilder
appendBitString !x' =
  bitStringBuilder $
  \(BitStringBuilderState !builder !buff !totalSizeIn) -> go x' builder buff totalSizeIn
  where go !x !builder !buff !totalSize
          | bitStringLength x == 0 = BitStringBuilderState builder buff totalSize
          | otherwise =
            let (!rest, !buff') = bufferBits x buff
            in if bitStringBuilderChunkSpaceLeft buff' > 0
                  then BitStringBuilderState builder buff' totalSize
                  else let !nextBuilder =
                             builder <>
                             SB.word64BE (bitStringBuilderChunkContent buff')
                           !totalSize' = totalSize + bitStringMaxLengthBytes
                       in go rest nextBuilder emptyBitStringBuilderChunk totalSize'

-- | Write all the b*y*tes, into the 'BitStringBuilderState' this allows general
-- purposes non-byte aligned builders.
appendStrictByteString :: SB.ByteString -> BitStringBuilder
appendStrictByteString !sb =
  foldMap (appendBitString . bitString 8 . fromIntegral) (SB.unpack sb)

runBitStringBuilderHoley
  :: FunctionBuilder BitStringBuilder SB.Builder a -> a
runBitStringBuilderHoley (FB !x) = x runBitStringBuilder

-- * 'BitString' construction from 'BitRecord's

class BitStringBuilderHoley a r where
  type ToBitStringBuilder a r
  type ToBitStringBuilder a r = r
  bitStringBuilderHoley :: a -> FunctionBuilder BitStringBuilder r (ToBitStringBuilder a r)

instance BitStringBuilderHoley BitString r where
  bitStringBuilderHoley = immediate . appendBitString

-- ** 'BitRecordField' instances

type family UnsignedDemoteRep i where
  UnsignedDemoteRep Int8  = Word8
  UnsignedDemoteRep Int16 = Word16
  UnsignedDemoteRep Int32 = Word32
  UnsignedDemoteRep Int64 = Word64

-- *** BitFields

instance
  forall (nested :: BitField rt st s) a .
   ( BitStringBuilderHoley (Proxy nested) a )
  => BitStringBuilderHoley (Proxy (Konst nested)) a where
  type ToBitStringBuilder (Proxy (Konst nested)) a =
    ToBitStringBuilder (Proxy nested) a
  bitStringBuilderHoley _ = bitStringBuilderHoley (Proxy @nested)


-- *** Labbeled Fields

instance
  forall nested l a .
   ( BitStringBuilderHoley (Proxy nested) a )
  => BitStringBuilderHoley (Proxy (LabelF l nested)) a where
  type ToBitStringBuilder (Proxy (LabelF l nested)) a =
    ToBitStringBuilder (Proxy nested) a
  bitStringBuilderHoley _ = bitStringBuilderHoley (Proxy @nested)

instance
  forall (nested :: To (BitField rt st s)) l a .
   ( BitStringBuilderHoley (Proxy nested) a )
  => BitStringBuilderHoley (Proxy (Labelled l nested)) a where
  type ToBitStringBuilder (Proxy (Labelled l nested)) a =
    ToBitStringBuilder (Proxy nested) a
  bitStringBuilderHoley _ = bitStringBuilderHoley (Proxy @nested)

-- **** Bool

instance forall f a . (BitRecordFieldSize f ~ 1) =>
  BitStringBuilderHoley (Proxy (f := 'True)) a where
  bitStringBuilderHoley _ = immediate (appendBitString (bitString 1 1))

instance forall f a . (BitRecordFieldSize f ~ 1) =>
  BitStringBuilderHoley (Proxy (f := 'False)) a where
  bitStringBuilderHoley _ = immediate (appendBitString (bitString 1 0))

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldFlag)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldFlag)) a = Bool -> a
  bitStringBuilderHoley _ =
    addParameter (appendBitString . bitString 1 . (\ !t -> if t then 1 else 0))

-- new:

instance forall f a . (BitFieldSize (From f) ~ 1) =>
  BitStringBuilderHoley (Proxy (f :=. 'True)) a where
  bitStringBuilderHoley _ = immediate (appendBitString (bitString 1 1))

instance forall f a . (BitFieldSize (From f) ~ 1) =>
  BitStringBuilderHoley (Proxy (f :=. 'False)) a where
  bitStringBuilderHoley _ = immediate (appendBitString (bitString 1 0))

instance forall a .
  BitStringBuilderHoley (Proxy 'MkFieldFlag) a where
  type ToBitStringBuilder (Proxy 'MkFieldFlag) a = Bool -> a
  bitStringBuilderHoley _ =
    addParameter (appendBitString . bitString 1 . (\ !t -> if t then 1 else 0))

-- **** Bits

instance forall (s :: Nat) a . (KnownChunkSize s) =>
  BitStringBuilderHoley (Proxy (MkField ('MkFieldBits :: BitField (B s) Nat s))) a where
  type ToBitStringBuilder (Proxy (MkField ('MkFieldBits :: BitField (B s) Nat s))) a = B s -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitStringProxyLength (Proxy @s) . unB)

-- **** Naturals

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldU64)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldU64)) a = Word64 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 64)

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldU32)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldU32)) a = Word32 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 32 . fromIntegral)

instance forall a .
  BitStringBuilderHoley (Proxy 'MkFieldU32) a where
  type ToBitStringBuilder (Proxy 'MkFieldU32) a = Word32 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 32 . fromIntegral)

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldU16)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldU16)) a = Word16 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 16 . fromIntegral)

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldU8)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldU8)) a = Word8 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 8 . fromIntegral)

-- **** Signed

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldI64)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldI64)) a = Int64 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 64 . fromIntegral @Int64 @Word64)

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldI32)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldI32)) a = Int32 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 32 . fromIntegral . fromIntegral @Int32 @Word32)

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldI16)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldI16)) a = Int16 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 16 . fromIntegral . fromIntegral @Int16 @Word16)

instance forall a .
  BitStringBuilderHoley (Proxy (MkField 'MkFieldI8)) a where
  type ToBitStringBuilder (Proxy (MkField 'MkFieldI8)) a = Int8 -> a
  bitStringBuilderHoley _ = addParameter (appendBitString . bitString 8 . fromIntegral . fromIntegral @Int8 @Word8)

-- *** Assign static values

instance forall (f :: To (BitRecordField (t :: BitField rt Nat len))) (v :: Nat) a . (KnownNat v, BitStringBuilderHoley (Proxy f) a, ToBitStringBuilder (Proxy f) a ~ (rt -> a), Num rt) =>
  BitStringBuilderHoley (Proxy (f := v)) a where
  bitStringBuilderHoley _ = fillParameter (bitStringBuilderHoley (Proxy @f)) (fromIntegral (natVal (Proxy @v)))

instance forall v f a x . (KnownNat v, BitStringBuilderHoley (Proxy f) a, ToBitStringBuilder (Proxy f) a ~ (x -> a), Num x) =>
  BitStringBuilderHoley (Proxy (f := ('PositiveNat v))) a where
  bitStringBuilderHoley _ =  fillParameter (bitStringBuilderHoley (Proxy @f)) (fromIntegral (natVal (Proxy @v)))


instance forall v f a x . (KnownNat v, BitStringBuilderHoley (Proxy f) a, ToBitStringBuilder (Proxy f) a ~ (x -> a), Num x) =>
  BitStringBuilderHoley (Proxy (f := ('NegativeNat v))) a where
  bitStringBuilderHoley _ = fillParameter (bitStringBuilderHoley (Proxy @f)) (fromIntegral (-1 * (natVal (Proxy @v))))

-- new:

instance
  forall (f :: To (BitField rt Nat len)) (v :: Nat) a .
  ( KnownNat v
  , BitStringBuilderHoley (Proxy f) a
  , ToBitStringBuilder (Proxy f) a ~ (rt -> a)
  , Num rt)
  =>
  BitStringBuilderHoley (Proxy (f :=. v)) a where
  bitStringBuilderHoley _ =
    fillParameter
      (bitStringBuilderHoley (Proxy @f))
      (fromIntegral (natVal (Proxy @v)))

-- instance forall v f a x . (KnownNat v, BitStringBuilderHoley (Proxy f) a, ToBitStringBuilder (Proxy f) a ~ (x -> a), Num x) =>
--   BitStringBuilderHoley (Proxy (f := ('PositiveNat v))) a where
--   bitStringBuilderHoley _ =  fillParameter (bitStringBuilderHoley (Proxy @f)) (fromIntegral (natVal (Proxy @v)))


-- instance forall v f a x . (KnownNat v, BitStringBuilderHoley (Proxy f) a, ToBitStringBuilder (Proxy f) a ~ (x -> a), Num x) =>
--   BitStringBuilderHoley (Proxy (f := ('NegativeNat v))) a where
--   bitStringBuilderHoley _ = fillParameter (bitStringBuilderHoley (Proxy @f)) (fromIntegral (-1 * (natVal (Proxy @v))))


-- ** 'BitRecord' instances

instance forall (r :: To BitRecord) a . BitStringBuilderHoley (Proxy (From r)) a =>
  BitStringBuilderHoley (Proxy r) a where
  type ToBitStringBuilder (Proxy r) a =
    ToBitStringBuilder (Proxy (From r)) a
  bitStringBuilderHoley _ = bitStringBuilderHoley (Proxy @(From r))

-- *** 'BitRecordMember'

instance forall f a . BitStringBuilderHoley (Proxy f) a => BitStringBuilderHoley (Proxy ('BitRecordMember f)) a where
  type ToBitStringBuilder (Proxy ('BitRecordMember f)) a = ToBitStringBuilder (Proxy f) a
  bitStringBuilderHoley _ = bitStringBuilderHoley (Proxy @f)

-- *** 'RecordField'


instance forall f a . BitStringBuilderHoley (Proxy f) a
  => BitStringBuilderHoley (Proxy ('RecordField f)) a where
  type ToBitStringBuilder (Proxy ('RecordField f)) a =
        ToBitStringBuilder (Proxy f) a
  bitStringBuilderHoley _ = bitStringBuilderHoley (Proxy @f)


-- *** 'AppendedBitRecords'

instance forall l r a .
  (BitStringBuilderHoley (Proxy l) (ToBitStringBuilder (Proxy r) a)
  , BitStringBuilderHoley (Proxy r) a)
   => BitStringBuilderHoley (Proxy ('BitRecordAppend l r)) a where
  type ToBitStringBuilder (Proxy ('BitRecordAppend l r)) a =
    ToBitStringBuilder (Proxy l) (ToBitStringBuilder (Proxy r) a)
  bitStringBuilderHoley _ = bitStringBuilderHoley (Proxy @l) . bitStringBuilderHoley (Proxy @r)

-- *** 'EmptyBitRecord' and '...Pretty'

instance BitStringBuilderHoley (Proxy 'EmptyBitRecord) a where
  bitStringBuilderHoley _ = id

-- ** Tracing/Debug Printing

-- | Print a 'SB.Builder' to a space seperated series of hexa-decimal bytes.
printBuilder :: SB.Builder -> String
printBuilder b =
  ("<< " ++) $
  (++ " >>") $ unwords $ printf "%0.2x" <$> B.unpack (SB.toLazyByteString b)

bitStringPrinter
  :: BitStringBuilderHoley a String
  => a -> ToBitStringBuilder a String
bitStringPrinter =
  toFunction . mapAccumulator (printBuilder . runBitStringBuilder) . bitStringBuilderHoley
