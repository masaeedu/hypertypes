-- | A convinience module which re-exports common functionality of the hypertypes library

module Hyper (module X) where

import Data.Constraint as X (Constraint, Dict(..), withDict)
import Data.Functor.Const as X (Const(..))
import Data.Proxy as X (Proxy(..))
import GHC.Generics as X (Generic, (:*:)(..))
import Hyper.Class.Apply as X (HApply(..), HApplicative, liftH2)
import Hyper.Class.Foldable as X (HFoldable(..), hfoldMap, hfolded1, htraverse_, htraverse1_)
import Hyper.Class.Functor as X (HFunctor(..), hmapped1)
import Hyper.Class.HasPlain as X (HasHPlain(..))
import Hyper.Class.Nodes as X (HNodes(..), HWitness(..), _HWitness, (#>), (#*#))
import Hyper.Class.Pointed as X (HPointed(..))
import Hyper.Class.Recursive as X (Recursively(..), RNodes, RTraversable)
import Hyper.Class.Traversable as X (HTraversable(..), htraverse, htraverse1)
import Hyper.Combinator.Ann as X
import Hyper.Combinator.ANode as X
import Hyper.Combinator.Compose as X (HCompose(..), _HCompose, hcomposed)
import Hyper.Combinator.Flip as X
import Hyper.Combinator.Func as X
import Hyper.TH.Apply as X (makeHApplicativeBases)
import Hyper.TH.Context as X (makeHContext)
import Hyper.TH.HasPlain as X (makeHasHPlain)
import Hyper.TH.Traversable as X (makeHTraversableApplyAndBases, makeHTraversableAndBases)
import Hyper.TH.ZipMatch as X (makeZipMatch)
import Hyper.Type as X
import Hyper.Type.Pure as X
