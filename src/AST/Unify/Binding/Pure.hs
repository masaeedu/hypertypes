{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, TypeFamilies, DataKinds #-}

module AST.Unify.Binding.Pure
    ( PureBinding(..), _PureBinding
    , emptyPureBinding
    , pureBinding
    ) where

import           AST.Knot (Tree)
import           AST.Unify.Binding (Binding(..))
import           AST.Unify.Term
import qualified Control.Lens as Lens
import           Control.Lens (ALens')
import           Control.Lens.Operators
import           Control.Monad.State (MonadState(..))
import           Data.Functor.Const (Const(..))
import           Data.Sequence
import qualified Data.Sequence as Sequence

import           Prelude.Compat

newtype PureBinding t = PureBinding (Seq (UTerm (Const Int) t))
Lens.makePrisms ''PureBinding

emptyPureBinding :: PureBinding t
emptyPureBinding = PureBinding mempty

pureBinding ::
    MonadState s m =>
    ALens' s (Tree PureBinding t) ->
    Binding (Const Int) m t
pureBinding l =
    Binding
    { lookupVar =
        \k ->
        Lens.use (Lens.cloneLens l . _PureBinding)
        <&> (`Sequence.index` (k ^. Lens._Wrapped))
    , newVar =
        \x ->
        do
            s <- Lens.use (Lens.cloneLens l . _PureBinding)
            Const (Sequence.length s) <$ (Lens.cloneLens l . _PureBinding .= s Sequence.|> x)
    , bindVar = bind
    }
    where
        bind k v = Lens.cloneLens l . _PureBinding %= Sequence.update (k ^. Lens._Wrapped) v
