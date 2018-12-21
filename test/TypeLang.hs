{-# LANGUAGE StandaloneDeriving, UndecidableInstances, TemplateHaskell, TypeFamilies, FlexibleInstances, MultiParamTypeClasses, FlexibleContexts, DataKinds #-}

module TypeLang where

import AST
import AST.Class.Instantiate
import AST.Unify
import AST.Unify.IntMapBinding
import AST.Unify.STBinding
import AST.Term.FuncType
import AST.Term.Scope
import Control.Lens (ALens')
import qualified Control.Lens as Lens
import Control.Lens.Operators
import Control.Monad.RWS
import Control.Monad.Reader
import Control.Monad.ST
import Control.Monad.ST.Class (MonadST(..))
import Control.Monad.Trans.Maybe
import Data.Functor.Const
import Data.STRef

data Typ f
    = TInt
    | TFun (FuncType Typ f)
    | TRow (Row f)
    | TVar String

data Row f
    = REmpty
    | RExtend String (Tie f Typ) (Tie f Row)
    | RVar String

data Types f = Types
    { _tTyp :: Tie f Typ
    , _tRow :: Tie f Row
    }

Lens.makePrisms ''Typ
Lens.makePrisms ''Row
Lens.makeLenses ''Types
makeChildrenAndZipMatch [''Typ, ''Row, ''Types]

deriving instance SubTreeConstraint Typ f Show => Show (Typ f)
deriving instance SubTreeConstraint Row f Show => Show (Row f)

type IntInferState = (Tree Types IntBindingState, Tree Types (Const Int))

emptyIntInferState :: IntInferState
emptyIntInferState =
    ( Types emptyIntBindingState emptyIntBindingState
    , Types (Const 0) (Const 0)
    )

instance Instantiate Typ

instance HasQuantifiedVar Typ where
    type QVar Typ = String
    quantifiedVar = _TVar

instance HasQuantifiedVar Row where
    type QVar Row = String
    quantifiedVar = _RVar

type IntInfer r w = RWST r w IntInferState Maybe

type instance UniVar (IntInfer r w) = Const Int

instance Monoid w => Unify (IntInfer r w) Typ where
    binding = intBindingState (Lens._1 . tTyp)
    newQuantifiedVariable _ = increase (Lens._2 . tTyp . Lens._Wrapped) <&> ('t':) . show

instance Monoid w => Unify (IntInfer r w) Row where
    binding = intBindingState (Lens._1 . tRow)
    newQuantifiedVariable _ = increase (Lens._2 . tRow . Lens._Wrapped) <&> ('r':) . show

instance Monoid w => Recursive (Unify (IntInfer r w)) Typ
instance Monoid w => Recursive (Unify (IntInfer r w)) Row

type STInferState s = Tree Types (Const (STRef s Int))

type STInfer r s = ReaderT (r, STInferState s) (MaybeT (ST s))

type instance UniVar (STInfer r s) = STVar s

readModifySTRef :: STRef s a -> (a -> a) -> ST s (a, a)
readModifySTRef ref func =
    do
        old <- readSTRef ref
        let new = func old
        (old, new) <$ (new `seq` writeSTRef ref new)

newStQuantified ::
    (MonadReader (a, STInferState s) m, MonadST m) =>
    ALens' (STInferState s) (Const (STRef (World m) Int) (ast :: Knot)) -> m Int
newStQuantified l =
    Lens.view (Lens._2 . Lens.cloneLens l . Lens._Wrapped)
    >>= liftST . fmap fst . (`readModifySTRef` (+1))

instance Unify (STInfer r s) Typ where
    binding = stBindingState
    newQuantifiedVariable _ = newStQuantified tTyp <&> ('t':) . show

instance Unify (STInfer r s) Row where
    binding = stBindingState
    newQuantifiedVariable _ = newStQuantified tRow <&> ('r':) . show

instance Recursive (Unify (STInfer r s)) Typ
instance Recursive (Unify (STInfer r s)) Row

instance HasFuncType Typ where
    funcType = _TFun

instance HasScopeTypes v Typ a => HasScopeTypes v Typ (a, x) where
    scopeTypes = Lens._1 . scopeTypes
