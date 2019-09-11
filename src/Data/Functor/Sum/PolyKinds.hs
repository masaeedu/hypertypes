{-# LANGUAGE DeriveDataTypeable, PolyKinds, Safe #-}
-- | @PolyKinds@ variant of base's `Data.Functor.Sum.Sum`.
--
-- See notes in "Data.Functor.Product.PolyKinds" for more info

module Data.Functor.Sum.PolyKinds (Sum(..)) where

import Control.Applicative ((<|>))
import Data.Data (Data)
import Data.Functor.Classes
import GHC.Generics (Generic, Generic1)

import Prelude.Compat

-- | A @PolyKinds@ variant of 'Data.Functor.Sum.Sum'.
--
-- Note that the original 'Data.Functor.Sum.Sum' is poly-kinded
-- in its type, but not in its instances such as 'Eq'.
data Sum f g a = InL (f a) | InR (g a)
    deriving (Data, Generic, Generic1, Eq, Ord, Read, Show)

instance (Eq1 f, Eq1 g) => Eq1 (Sum f g) where
    liftEq eq (InL x1) (InL x2) = liftEq eq x1 x2
    liftEq _ (InL _) (InR _) = False
    liftEq _ (InR _) (InL _) = False
    liftEq eq (InR y1) (InR y2) = liftEq eq y1 y2

instance (Ord1 f, Ord1 g) => Ord1 (Sum f g) where
    liftCompare comp (InL x1) (InL x2) = liftCompare comp x1 x2
    liftCompare _ (InL _) (InR _) = LT
    liftCompare _ (InR _) (InL _) = GT
    liftCompare comp (InR y1) (InR y2) = liftCompare comp y1 y2

instance (Read1 f, Read1 g) => Read1 (Sum f g) where
    liftReadPrec rp rl =
        readData $
        readUnaryWith (liftReadPrec rp rl) "InL" InL <|>
        readUnaryWith (liftReadPrec rp rl) "InR" InR

    liftReadListPrec = liftReadListPrecDefault
    liftReadList     = liftReadListDefault

instance (Show1 f, Show1 g) => Show1 (Sum f g) where
    liftShowsPrec sp sl d (InL x) =
        showsUnaryWith (liftShowsPrec sp sl) "InL" d x
    liftShowsPrec sp sl d (InR y) =
        showsUnaryWith (liftShowsPrec sp sl) "InR" d y

instance (Functor f, Functor g) => Functor (Sum f g) where
    fmap f (InL x) = InL (fmap f x)
    fmap f (InR y) = InR (fmap f y)

    a <$ (InL x) = InL (a <$ x)
    a <$ (InR y) = InR (a <$ y)

instance (Foldable f, Foldable g) => Foldable (Sum f g) where
    foldMap f (InL x) = foldMap f x
    foldMap f (InR y) = foldMap f y

instance (Traversable f, Traversable g) => Traversable (Sum f g) where
    traverse f (InL x) = InL <$> traverse f x
    traverse f (InR y) = InR <$> traverse f y