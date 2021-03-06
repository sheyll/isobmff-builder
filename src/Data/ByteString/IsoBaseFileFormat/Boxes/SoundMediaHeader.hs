-- | Media-independent properties of a tracks sound content.
module Data.ByteString.IsoBaseFileFormat.Boxes.SoundMediaHeader where

import Data.ByteString.IsoBaseFileFormat.Box
import Data.ByteString.IsoBaseFileFormat.Util.BoxFields
import Data.ByteString.IsoBaseFileFormat.Util.FullBox
import Data.ByteString.IsoBaseFileFormat.Boxes.Handler
import Data.ByteString.IsoBaseFileFormat.Boxes.SpecificMediaHeader
import Data.ByteString.IsoBaseFileFormat.ReExports

type instance MediaHeaderFor 'AudioTrack = SoundMediaHeader

-- | Sound header data box.
newtype SoundMediaHeader where
  SoundMediaHeader
   :: Template (I16 "balance") 0
   :+ Constant (U16 "reserved") 0
   -> SoundMediaHeader
   deriving (Default, IsBoxContent)

-- | Create a sound media header data box.
soundMediaHeader :: SoundMediaHeader -> Box (FullBox SoundMediaHeader 0)
soundMediaHeader = fullBox 0

instance IsBox SoundMediaHeader
type instance BoxTypeSymbol SoundMediaHeader = "smhd"
