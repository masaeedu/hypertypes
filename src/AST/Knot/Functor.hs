-- | Functors as Knots
{-# LANGUAGE TemplateHaskell, TypeFamilies, StandaloneDeriving, FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses #-}
{-# LANGUAGE ConstraintKinds, DerivingStrategies, DeriveGeneric #-}
module AST.Knot.Functor
    ( ToKnot(..), _ToKnot
    ) where

import AST.Class.Applicative.TH (makeKApplicativeAndBase)
import AST.Class.Children.TH (makeChildren)
import AST.Class.Recursive (Recursive)
import AST.Combinator.Single (Single(..))
import AST.Knot (Tree, Tie, ChildrenTypesOf)
import Control.DeepSeq (NFData)
import Control.Lens (Iso, iso)
import Data.Binary (Binary)
import GHC.Generics (Generic)

newtype ToKnot f k = MkToKnot (f (Tie k (ToKnot f)))
    deriving stock Generic

_ToKnot ::
    Iso (Tree (ToKnot f0) k0)
        (Tree (ToKnot f1) k1)
        (f0 (Tree k0 (ToKnot f0)))
        (f1 (Tree k1 (ToKnot f1)))
_ToKnot = iso (\(MkToKnot x) -> x) MkToKnot

type instance ChildrenTypesOf (ToKnot f) = Single (ToKnot f)

makeKApplicativeAndBase ''ToKnot
makeChildren ''ToKnot

instance (Traversable f, c (ToKnot f)) => Recursive c (ToKnot f)

type InToKnot f k = f (Tie k (ToKnot f))
deriving instance Eq     (InToKnot f k) => Eq     (ToKnot f k)
deriving instance Ord    (InToKnot f k) => Ord    (ToKnot f k)
deriving instance Show   (InToKnot f k) => Show   (ToKnot f k)
instance Binary (InToKnot f k) => Binary (ToKnot f k)
instance NFData (InToKnot f k) => NFData (ToKnot f k)
