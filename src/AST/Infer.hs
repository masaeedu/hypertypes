{-# LANGUAGE ScopedTypeVariables, FlexibleContexts #-}

module AST.Infer
    ( module AST.Class.Infer
    , module AST.Infer.Result
    , module AST.Infer.ScopeLevel
    , module AST.Infer.Term
    , infer
    ) where

import AST
import AST.Class.Infer
import AST.Infer.Result
import AST.Infer.ScopeLevel
import AST.Infer.Term
import AST.Unify (UVarOf)
import Control.Lens.Operators
import Data.Constraint (withDict)
import Data.Proxy (Proxy(..))

import Prelude.Compat

{-# INLINE infer #-}
infer ::
    forall m t a.
    (Recursively (Infer m) t, Recursively KFunctor t) =>
    Tree (Ann a) t ->
    m (Tree (ITerm a (UVarOf m)) t)
infer (Ann a x) =
    withDict (recursive @(Infer m) @t) $
    withDict (recursive @KFunctor @t) $
    inferBody
        (mapKWith (Proxy @'[Recursively (Infer m), Recursively KFunctor])
            (\c -> infer c <&> (\i -> InferredChild i (i ^. iRes)) & InferChild)
            x)
    <&> (\(InferRes xI t) -> ITerm a t xI)
