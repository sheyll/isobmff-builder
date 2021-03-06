{-# LANGUAGE UndecidableInstances #-}

module Data.ByteString.IsoBaseFileFormat.Util.TypeLayout where

import Data.Kind
import Data.Type.Bool
import Data.Type.Equality
import GHC.TypeLits

----
type family IsRuleConform (b :: k) (r :: l) :: Bool
----
data TopLevel  :: Type -> Type
type instance IsRuleConform t (TopLevel rule) = IsRuleConform t rule
----
data OneOf :: [Type] -> Type
type instance IsRuleConform t (OneOf '[]) = 'False
type instance IsRuleConform t (OneOf (r ': rs)) =
  IsRuleConform t r || IsRuleConform t (OneOf rs)
----
data MatchSymbol :: Symbol -> Type
type instance IsRuleConform b (MatchSymbol fourcc) = ToSymbol b == fourcc
type family ToSymbol t :: Symbol
----
data OnceOptionalX t
data SomeOptionalX t
data SomeMandatoryX t
type instance IsRuleConform (bs :: [Type]) (sq :: [Type]) = IsSequence bs sq
type family
  IsSequence (bs :: [k]) (rs :: [j]) :: Bool
  where
   IsSequence '[]       '[]                      = 'True
   IsSequence (b ': bs) '[]                      = 'False
   --
   IsSequence '[]       (OnceOptionalX r ': rs)  = IsSequence '[] rs
   IsSequence (b ': bs) (OnceOptionalX r ': rs)  =
     If (IsRuleConform b r)
        (IsSequence bs        rs)
        (IsSequence (b ': bs) rs)
   --
   IsSequence '[]       (SomeOptionalX r ': rs)  = IsSequence '[] rs
   IsSequence (b ': bs) (SomeOptionalX r ': rs)  =
     If (IsRuleConform b r)
        (IsSequence bs        (SomeOptionalX r ': rs))
        (IsSequence (b ': bs) rs                     )
   --
   IsSequence '[]       (SomeMandatoryX r ': rs)  = 'False
   IsSequence (b ': bs) (SomeMandatoryX r ': rs)  =
     IsRuleConform b r && IsSequence  bs (SomeOptionalX r ': rs)
   --
   IsSequence '[]       (r ': rs)  = 'False
   IsSequence (b ': bs) (r ': rs)  =
     IsRuleConform b r && IsSequence bs rs
