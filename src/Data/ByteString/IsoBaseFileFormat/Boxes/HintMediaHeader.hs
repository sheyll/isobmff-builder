-- | Media-independent properties of a hint tracks media content.
module Data.ByteString.IsoBaseFileFormat.Boxes.HintMediaHeader where

import Data.ByteString.IsoBaseFileFormat.Box
import Data.ByteString.IsoBaseFileFormat.Util.BoxFields
import Data.ByteString.IsoBaseFileFormat.Util.FullBox
import Data.ByteString.IsoBaseFileFormat.Boxes.Handler
import Data.ByteString.IsoBaseFileFormat.Boxes.SpecificMediaHeader
import Data.ByteString.IsoBaseFileFormat.ReExports

type instance MediaHeaderFor 'HintTrack = HintMediaHeader

-- | Hint data box.
newtype HintMediaHeader where
  HintMediaHeader
   :: U16 "maxPDUsize"
   :+ U16 "avgPDUsize"
   :+ U16 "maxbitrate"
   :+ U16 "avgbitrate"
   :+ U32 "reserved"
   -> HintMediaHeader
   deriving (Default, IsBoxContent)

-- | Create a hint media header data box.
hintMediaHeader :: HintMediaHeader -> Box (FullBox HintMediaHeader 0)
hintMediaHeader = fullBox 0

instance IsBox HintMediaHeader
type instance BoxTypeSymbol HintMediaHeader = "hmhd"
