{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, StandaloneDeriving, RankNTypes #-}
{-# LANGUAGE DeriveGeneric, FlexibleContexts, TypeFamilies, FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses, UndecidableInstances, ConstraintKinds #-}

module AST.Knot.Ann
    ( Ann(..), ann, val
    , annotations, strip
    , para
    ) where

import           AST.Class.Children (Children(..))
import           AST.Class.Recursive (Recursive, unwrap, recursiveChildren, recursiveOverChildren)
import           AST.Class.ZipMatch.TH (makeChildrenAndZipMatch)
import           AST.Knot (Tie, Tree)
import           AST.Knot.Pure (Pure(..))
import           Control.DeepSeq (NFData)
import           Control.Lens (Traversal, makeLenses)
import           Control.Lens.Operators
import           Data.Binary (Binary)
import           Data.Constraint (Constraint)
import           Data.Proxy (Proxy(..))
import           GHC.Generics (Generic)
import qualified Text.PrettyPrint as PP
import           Text.PrettyPrint.HughesPJClass (Pretty(..), maybeParens)

import           Prelude.Compat

-- Annotate tree nodes
data Ann a knot = Ann
    { _ann :: a
    , _val :: Tie knot (Ann a)
    } deriving Generic
makeLenses ''Ann

makeChildrenAndZipMatch ''Ann
instance c (Ann a) => Recursive c (Ann a)

instance Deps Pretty a t => Pretty (Ann a t) where
    pPrintPrec lvl prec (Ann pl b)
        | PP.isEmpty plDoc || plDoc == PP.text "()" = pPrintPrec lvl prec b
        | otherwise =
            maybeParens (13 < prec) $ mconcat
            [ pPrintPrec lvl 14 b, PP.text "{", plDoc, PP.text "}" ]
        where
            plDoc = pPrintPrec lvl 0 pl

annotations ::
    Recursive Children e =>
    Traversal
    (Tree (Ann a) e)
    (Tree (Ann b) e)
    a b
annotations f (Ann pl x) =
    Ann <$> f pl <*> recursiveChildren (Proxy :: Proxy Children) (annotations f) x

-- Similar to `para` from `recursion-schemes`,
-- except it's int term of full annotated trees rather than just the final result.
-- TODO: What does the name `para` mean?
para ::
    Recursive constraint expr =>
    Proxy constraint ->
    (forall child. Recursive constraint child => Tree child (Ann a) -> a) ->
    Tree Pure expr ->
    Tree (Ann a) expr
para p f x =
    Ann (f r) r
    where
        r = recursiveOverChildren p (para p f) (getPure x)

strip :: Recursive Children expr => Tree (Ann a) expr -> Tree Pure expr
strip = unwrap (Proxy :: Proxy Children) (^. val)

type Deps c a t = ((c a, c (Tie t (Ann a))) :: Constraint)
deriving instance Deps Eq   a t => Eq   (Ann a t)
deriving instance Deps Ord  a t => Ord  (Ann a t)
deriving instance Deps Show a t => Show (Ann a t)
instance Deps Binary a t => Binary (Ann a t)
instance Deps NFData a t => NFData (Ann a t)
