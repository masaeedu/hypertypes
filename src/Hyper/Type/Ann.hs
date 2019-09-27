-- | A 'Hyper.Type.HyperType' which adds an annotation to every node in a tree

{-# LANGUAGE TemplateHaskell, UndecidableInstances, FlexibleInstances, FlexibleContexts #-}

module Hyper.Type.Ann
    ( Ann(..), ann, val, HWitness(..)
    , annotations
    , strip, addAnnotations
    ) where

import           Control.Lens (Traversal, makeLenses)
import           Control.Lens.Operators
import           Data.Constraint (withDict)
import           Data.Proxy (Proxy(..))
import           GHC.Generics (Generic)
import           Generics.Constraints (Constraints)
import           Hyper.Class.Functor (HFunctor(..))
import           Hyper.Class.Monad
import           Hyper.Class.Nodes (HNodes(..), (#>))
import           Hyper.Class.Traversable (htraverse)
import           Hyper.Recurse
import           Hyper.TH.Internal.Instances (makeCommonInstances)
import           Hyper.TH.Traversable (makeHTraversableApplyAndBases)
import           Hyper.TH.ZipMatch (makeZipMatch)
import           Hyper.Type (Tree, type (#))
import           Hyper.Type.Combinator.Compose
import           Hyper.Type.Pure (Pure(..))
import qualified Text.PrettyPrint as PP
import           Text.PrettyPrint.HughesPJClass (Pretty(..), maybeParens)

import           Prelude.Compat

-- | A 'Hyper.Type.HyperType' which adds an annotation to every node in a tree
data Ann a h = Ann
    { _ann :: a
    , _val :: h # Ann a
    } deriving Generic
makeLenses ''Ann

makeCommonInstances [''Ann]
makeHTraversableApplyAndBases ''Ann
makeZipMatch ''Ann

instance c (Ann a) => Recursively c (Ann a)
instance RNodes (Ann a)
instance RTraversable (Ann a)

instance Monoid a => HMonad (Ann a) where
    hjoin (MkCompose (Ann a0 (MkCompose (Ann a1 (MkCompose x))))) =
        Ann (a0 <> a1) (t x)
        where
            t ::
                forall p.
                Recursively HFunctor p =>
                Tree p (Compose (Ann a) (Ann a)) ->
                Tree p (Ann a)
            t =
                withDict (recursively (Proxy @(HFunctor p))) $
                hmap (Proxy @(Recursively HFunctor) #> hjoin)

instance Constraints (Ann a t) Pretty => Pretty (Ann a t) where
    pPrintPrec lvl prec (Ann pl b)
        | PP.isEmpty plDoc || plDoc == PP.text "()" = pPrintPrec lvl prec b
        | otherwise =
            maybeParens (13 < prec) $ mconcat
            [ pPrintPrec lvl 14 b, PP.text "{", plDoc, PP.text "}" ]
        where
            plDoc = pPrintPrec lvl 0 pl

-- | A 'Traversal' from an annotated tree to its annotations
annotations ::
    forall h a b.
    RTraversable h =>
    Traversal
    (Tree (Ann a) h)
    (Tree (Ann b) h)
    a b
annotations f (Ann pl x) =
    withDict (recurse (Proxy @(RTraversable h))) $
    Ann
    <$> f pl
    <*> htraverse (Proxy @RTraversable #> annotations f) x

-- | Remove a tree's annotations
strip ::
    Recursively HFunctor expr =>
    Tree (Ann a) expr ->
    Tree Pure expr
strip = unwrap (const (^. val))

-- | Compute annotations for a tree from the bottom up
addAnnotations ::
    Recursively HFunctor h =>
    (forall n. HRecWitness h n -> Tree n (Ann a) -> a) ->
    Tree Pure h ->
    Tree (Ann a) h
addAnnotations f = wrap (\w x -> Ann (f w x) x)
