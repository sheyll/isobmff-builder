{-# LANGUAGE UndecidableInstances #-}
-- | NamedStructure definition for sequences of bits.
--
-- This module provides the core data types and functions for
-- conversion of finite bit sequences from an to conventional (Haskell) data types.
--
-- Non-compressed, non-random finite bit sequences generated by programs are
-- usually compositions of bytes and multi byte words, and a ton of Haskell libraries
-- exist for the serialization and deserialization of ByteStrings.
--
-- This module allows the definition of a __structure__ i.e. a very simple grammar,
-- which allows functions in this library to read and write single bytes, words and bits.
--
-- Also complete bit sequence may be constructed or destructed from and to Haskell types.
--
-- Further more, the Record may contain dependent sub-sequences, for example to
-- express Record that precede a /length/ field before a repetitive block data.
--
-- Antother example for dependent sequences is /fields/ whose presence depends on
-- /flags/ preceding them.
--
-- This library is also designed with /zero copying/ in mind.
--
-- It should be emphasized that binary deserialization __is not__
-- to be confused with binary destructuring. While the former usually involves copying
-- all regular sub sequences from the input to a value of a certain type, the later
-- merely requires to peek into the sequeuence at a certain position and deserializing
-- a sub sequence. The starting position and the interpretation are governed by the
-- strucuture applied to the sequence.

module Data.Type.BitRecords.Structure where

import           Data.Int
import           Data.Kind                      ( Type )
import           Data.Kind.Extra
import           Data.Proxy
import           Data.Type.Pretty
import           Data.Word
import           GHC.TypeLits
import           Data.Type.Bool
import           Data.Type.Equality             (type (==))
import           Test.TypeSpec
import qualified Data.Type.BitRecords.Structure.TypeLits as Literal

-- | Phantom type for structures
data Structure (sizeType :: StructureSizeType) where
  MkVariableStructure :: Structure 'VarSize
  MkFixStructure :: Structure 'FixSize

-- | 'Structure's that have statically known fixed size.
type FixStructure = Structure 'FixSize

-- | 'Structure's that have __no__ statically known fixed size.
type VariableStructure = Structure 'VarSize

-- | Phantom type indicating that if a 'Structure' has a statically known size.
data StructureSizeType = VarSize | FixSize

-- | The number of bits that a structure with a predetermined fixed size requires.
type family GetStructureSize (t :: Extends (Structure 'FixSize)) :: Nat

-- | Support for Pretty Printing 'Structure' Types
type family PrettyStructure (struct :: Extends (Structure sizeType)) :: PrettyType
type instance ToPretty (struct :: Extends (Structure sizeType)) = PrettyStructure struct

-- | Empty Structure
data EmptyStructure :: Extends (Structure 'FixSize)

type instance GetStructureSize EmptyStructure = 0
type instance PrettyStructure EmptyStructure = 'PrettyEmpty

type instance GetStructureSize (Anonymous (Name name struct)) = GetStructureSize struct
type instance PrettyStructure (Anonymous (Name name struct)) = name <:> PrettyStructure struct

-- | A record is a list of fields, 'Name' 'Structure' composed of a list of other Record in natural order.
data Record :: [Extends (Named (Structure sizeType))] -> Extends (Structure sizeType)

type instance GetStructureSize (Record '[]) = 0
type instance GetStructureSize (Record (x ': xs)) = GetStructureSize (Anonymous x) + GetStructureSize (Record xs)

type instance PrettyStructure (Record xs) = "Record" <:$$--> PrettyRecord xs

type family (<>) (a :: Extends (Named (Structure sizeType))) (b :: k) :: Extends (Structure sizeType) where
  a <> (b :: Extends (Named (Structure sizeType))) = Record '[a, b]
  a <> (Record xs) = Record (a ': xs)
infixr 6 <>

type family PrettyRecord (xs :: [Extends (Named (Structure sizeType))]) :: PrettyType where
  PrettyRecord '[] = 'PrettyEmpty
  PrettyRecord (x ': xs) =
    (PutStr "-" <+> PrettyStructure (Anonymous x)) <$$> PrettyRecord xs


-- | A variable length structure filled with any storable value
data AnyStructure (content :: k) :: Extends (Structure 'VarSize)
type instance PrettyStructure (AnyStructure c) = "AnyStructure" <:$$--> ToPretty c

-- | A fixed length sequence of bits.
data BitSequence (length :: Nat) :: Extends (Structure 'FixSize)

type family WithValidBitSequenceLength (length :: Nat) (out :: k) :: k where
  WithValidBitSequenceLength length out =
    If (length <=? 64 && 1 <=? length )
      out
      (TypeError ('Text "invalid bit sequence length: " ':<>: 'ShowType length))

type family (//) (name :: Symbol) (length :: Nat) :: Extends (Named (Structure 'FixSize)) where
  name // length =
    WithValidBitSequenceLength length (Name name (BitSequence length))

infixr 7 //

type instance GetStructureSize (BitSequence length) =
  WithValidBitSequenceLength length length
type instance PrettyStructure (BitSequence length) =
  WithValidBitSequenceLength length (PutStr "BitSequence " <+> PutNat length)

-- | A constant, fixed length sequence of bits, generated by a type level 'LiteralFamily'.
data LiteralStructure a :: Extends (Structure 'FixSize)

type instance GetStructureSize (LiteralStructure (Literal.Value s k (x :: k))) = Literal.SizeOf s x
type instance PrettyStructure (LiteralStructure (Literal.Value s k (x :: k))) = "LiteralStructure" <:> Literal.Pretty s x

-- | Compile time fixed content structure aliased to existing '(Structure 'FixSize)'.
data Assign :: Extends (Structure 'FixSize) -> Extends (Structure 'FixSize)  -> Extends (Structure 'FixSize)

type family AssignStructureValidateSize (lhs :: Extends (Structure 'FixSize)) (rhs :: Extends (Structure 'FixSize)) (out :: k) :: k where
  AssignStructureValidateSize lhs rhs out =
    If (GetStructureSize rhs <=? GetStructureSize lhs)
      out
      (TypeError ('Text "Assign value too big to fit into structure, the value " ':<>: 'ShowType rhs
                  ':<>: 'Text " requires " ':<>: 'ShowType (GetStructureSize rhs)
                  ':<>: 'Text " bits, but the structure "  ':<>: 'ShowType lhs
                  ':<>: 'Text " has only a size of " ':<>: 'ShowType (GetStructureSize lhs)
                  ':<>: 'Text " bits."))

type instance GetStructureSize (Assign lhs rhs) = AssignStructureValidateSize lhs rhs (GetStructureSize lhs)
type instance PrettyStructure (Assign lhs rhs) =
  AssignStructureValidateSize lhs rhs
    (PutStr "Assign" <+> PrettyStructure lhs <+> PrettyStructure rhs)


-- ** Integer Sequences

-- | A Wrapper for Haskell types. Users should implement the 'GetStructureSize' and 'Constructor' instances.
data TypeStructure :: Type -> Extends (Structure 'FixSize)

type U8 = TypeStructure Word8
type instance GetStructureSize (TypeStructure Word8) = 8
type instance PrettyStructure (TypeStructure Word8) = ToPretty Word8

type S8 = TypeStructure Int8
type instance GetStructureSize (TypeStructure Int8) = 8
type instance PrettyStructure (TypeStructure Int8) = ToPretty Int8

type FlagStructure = TypeStructure Bool
type instance GetStructureSize (TypeStructure Bool) = 1
type instance PrettyStructure (TypeStructure Bool) = ToPretty Bool

-- | (Structure 'FixSize) holding integral numbers
data IntegerStructure :: Nat -> Sign -> Endianess -> Extends (Structure 'FixSize) where
  S16LE :: Int16 -> IntegerStructure 16 'Signed 'LE 'MkFixStructure
  S16BE :: Int16 -> IntegerStructure 16 'Signed 'BE 'MkFixStructure
  U16LE :: Word16 -> IntegerStructure 16 'Unsigned 'LE 'MkFixStructure
  U16BE :: Word16 -> IntegerStructure 16 'Unsigned 'BE 'MkFixStructure
  S32LE :: Int32 -> IntegerStructure 32 'Signed 'LE 'MkFixStructure
  S32BE :: Int32 -> IntegerStructure 32 'Signed 'BE 'MkFixStructure
  U32LE :: Word32 -> IntegerStructure 32 'Unsigned 'LE 'MkFixStructure
  U32BE :: Word32 -> IntegerStructure 32 'Unsigned 'BE 'MkFixStructure
  S64LE :: Int64 -> IntegerStructure 64 'Signed 'LE 'MkFixStructure
  S64BE :: Int64 -> IntegerStructure 64 'Signed 'BE 'MkFixStructure
  U64LE :: Word64 -> IntegerStructure 64 'Unsigned 'LE 'MkFixStructure
  U64BE :: Word64 -> IntegerStructure 64 'Unsigned 'BE 'MkFixStructure

-- | Endianess of an 'IntegerStructure'
data Endianess = LE | BE

-- | Integer sign of an 'IntegerStructure'
data Sign = Signed | Unsigned

type family IntegerStructureValidateLength (n :: Nat) (out :: k) where
  IntegerStructureValidateLength n out =
    If (n == 16) out (If (n == 32) out (If (n == 64) out
      (TypeError ('Text "Invalid IntegerStructure size: " ':<>: 'ShowType n))))

type instance GetStructureSize (IntegerStructure n s e) = IntegerStructureValidateLength n n
type instance PrettyStructure (IntegerStructure n s e) =
  IntegerStructureValidateLength n
    (PutStr "IntegerStructure"
    <+> PutNat n
    <+> If (s == 'Signed) (PutStr "Signed") (PutStr "Unsigned")
    <+> If (e == 'BE) (PutStr "BE") (PutStr "LE"))

type U n e = IntegerStructure n 'Unsigned e
type S n e = IntegerStructure n 'Signed e

-- | (Structure 'FixSize) consisting of predefined type level literal values.


data ConditionalStructure (condition :: Bool) (ifStruct :: Extends (Structure 'FixSize)) (elseStruct :: Extends (Structure 'FixSize)) :: Extends (Structure 'FixSize)

type instance GetStructureSize (ConditionalStructure 'True l r) = GetStructureSize l
type instance GetStructureSize (ConditionalStructure 'False l r) = GetStructureSize r
type instance PrettyStructure (ConditionalStructure 'True l r) = PrettyStructure l
type instance PrettyStructure (ConditionalStructure 'False l r) = PrettyStructure r

-- * Structure PrettyType Printing

-- | Render @struct@ to a pretty, human readable form. Internally this is a wrapper
-- around 'ptShow' using 'PrettyStructure'.
showStructure
  :: forall proxy (struct :: Extends (Structure 'FixSize))
   . PrettyTypeShow (PrettyStructure struct)
  => proxy struct
  -> String
showStructure _ = showPretty (Proxy :: Proxy (PrettyStructure struct))

-- -------------------------------------------
-- Tests
-- -------------------------------------------

data BoolProxy (t :: Bool) where
  TrueProxy :: BoolProxy 'True
  FalseProxy :: BoolProxy 'False

_typeSpecGetStructureSize
  :: BoolProxy (testBool :: Bool)
  -> Expect [ GetStructureSize U8 `ShouldBe` 8
            , GetStructureSize EmptyStructure `ShouldBe` 0
            , GetStructureSize (Record [Name "x" U8, Name "y" U8]) `ShouldBe` 16
            , GetStructureSize (S 16 'BE) `ShouldBe` 16
            , GetStructureSize (ConditionalStructure testBool (U 32 'LE) S8) `ShouldBe` (If testBool 32 8)
            , GetStructureSize ("field 1"//3 <> "field 2"//2 <> "field 3"//5 <>
                          Name "field 4" ("field 4.1"//3 <> "field 4.2"//6))
                         `ShouldBe` 19
            , GetStructureSize (Assign (BitSequence 4) (LiteralStructure (Literal.Bits '[1,0,0,1]))) `ShouldBe` 4
            ]
_typeSpecGetStructureSize TrueProxy = Valid
_typeSpecGetStructureSize FalseProxy = Valid

_prettySpec :: String
_prettySpec =
  showPretty (Proxy @(
      PrettyHigh '[
         PrettyStructure EmptyStructure
       , PrettyStructure (Anonymous (Name "foo" U8))
       , PrettyStructure U8
       , PrettyStructure S8
       , PrettyStructure FlagStructure
       , PrettyStructure (S 16 'LE)
       , PrettyStructure (S 32 'LE)
       , PrettyStructure (S 64 'LE)
       , PrettyStructure (U 16 'LE)
       , PrettyStructure (U 32 'LE)
       , PrettyStructure (U 64 'LE)
       , PrettyStructure (S 16 'BE)
       , PrettyStructure (S 32 'BE)
       , PrettyStructure (S 64 'BE)
       , PrettyStructure (U 16 'BE)
       , PrettyStructure (U 32 'BE)
       , PrettyStructure (U 64 'BE)
       , PrettyStructure ("x"//32 <> "y"//32 <> "z"//8)
       , PrettyStructure (ConditionalStructure 'False S8 U8)
       , PrettyStructure (ConditionalStructure 'True S8 U8)
       , PrettyStructure (Assign S8 (LiteralStructure (Literal.To Nat 123)))
       , PrettyStructure (Assign S8 (LiteralStructure (Literal.NegativeInt 123)))
       , PrettyStructure (Assign FlagStructure (LiteralStructure (Literal.To Literal.Bit 1)))
       , PrettyStructure (LiteralStructure (Literal.Bits '[1,0,1,0]))
       , PrettyStructure (AnyStructure (U 64 'BE))
       , PrettyStructure ("foo" :# AnyStructure (U 64 'BE) <> "bar" :# AnyStructure Double)
       ]
      )
    )
