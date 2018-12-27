{-# LANGUAGE NoImplicitPrelude, DeriveGeneric, TemplateHaskell, TypeFamilies #-}
{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses, UndecidableInstances #-}
{-# LANGUAGE StandaloneDeriving, ConstraintKinds, DataKinds, TupleSections #-}
{-# LANGUAGE ScopedTypeVariables, FlexibleContexts #-}

module AST.Term.RowExtend
    ( RowExtend(..), rowFields, rowRest
    , updateRowChildConstraints, rowStructureMismatch, inferRowExtend
    ) where

import Algebra.Lattice (JoinSemiLattice(..))
import AST.Class.Children.Mono
import AST.Class.Infer (Infer(..), TypeAST, TypeOf, inferNode, nodeType)
import AST.Class.Recursive (Recursive(..), RecursiveConstraint, RecursiveDict)
import AST.Class.ZipMatch.TH (makeChildrenAndZipMatch)
import AST.Knot (Tree, Tie)
import AST.Knot.Ann (Ann)
import AST.Term.Map (TermMap, _TermMap, inferTermMap)
import AST.Unify (Unify(..), UVar, updateConstraints, newVar, unify, scopeConstraintsForType, newTerm)
import AST.Unify.Constraints (TypeConstraints(..))
import AST.Unify.Term (TypeConstraintsOf, UTermBody(..), UTerm(..))
import Control.DeepSeq (NFData)
import Control.Lens (makeLenses)
import Control.Lens.Operators
import Data.Binary (Binary)
import Data.Constraint (Constraint, withDict)
import Data.Map (keysSet)
import Data.Proxy (Proxy(..))
import Data.Set (Set)
import GHC.Generics (Generic)

import Prelude.Compat

-- | Row-extend primitive for use in both value-level and type-level
data RowExtend key val rest k = RowExtend
    { _rowFields :: TermMap key val k
    , _rowRest :: Tie k rest
    } deriving Generic

makeLenses ''RowExtend
makeChildrenAndZipMatch [''RowExtend]

instance
    RecursiveConstraint (RowExtend key val rest) constraint =>
    Recursive constraint (RowExtend key val rest)

type Deps c key val rest k = ((c key, c (Tie k val), c (Tie k rest)) :: Constraint)
deriving instance Deps Eq   key val rest k => Eq   (RowExtend key val rest k)
deriving instance Deps Ord  key val rest k => Ord  (RowExtend key val rest k)
deriving instance Deps Show key val rest k => Show (RowExtend key val rest k)
instance Deps Binary key val rest k => Binary (RowExtend key val rest k)
instance Deps NFData key val rest k => NFData (RowExtend key val rest k)

type instance TypeConstraintsOf (RowExtend key valTyp rowTyp) = TypeConstraintsOf rowTyp

fieldKeys :: TermMap key t k -> Set key
fieldKeys x = x ^. _TermMap & keysSet

updateRowChildConstraints ::
    forall m key valTyp rowTyp.
    (Unify m valTyp, Unify m rowTyp) =>
    (Set key -> TypeConstraintsOf rowTyp -> TypeConstraintsOf rowTyp) ->
    TypeConstraintsOf rowTyp ->
    Tree (RowExtend key valTyp rowTyp) (UVar m) ->
    m (Tree (RowExtend key valTyp rowTyp) (UVar m))
updateRowChildConstraints forbid c (RowExtend fields rest) =
    RowExtend
    <$> monoChildren (updateConstraints (constraintsFromScope (c ^. constraintsScope))) fields
    <*> updateConstraints (forbid (fieldKeys fields) c) rest

rowStructureMismatch ::
    forall m key valTyp rowTyp.
    ( Ord key
    , Recursive (Unify m) rowTyp
    , Unify m (RowExtend key valTyp rowTyp)
    ) =>
    (Set key -> TypeConstraintsOf rowTyp -> TypeConstraintsOf rowTyp) ->
    (Tree (RowExtend key valTyp rowTyp) (UVar m) -> m (Tree (UVar m) rowTyp)) ->
    Tree (UTermBody (UVar m)) (RowExtend key valTyp rowTyp) ->
    Tree (UTermBody (UVar m)) (RowExtend key valTyp rowTyp) ->
    m (Tree (RowExtend key valTyp rowTyp) (UVar m))
rowStructureMismatch forbid mkExtend
    (UTermBody c0 (RowExtend f0 r0))
    (UTermBody c1 (RowExtend f1 r1)) =
    withDict (recursive :: RecursiveDict (Unify m) rowTyp) $
    do
        restVar <- c0 \/ c1 & forbid (fieldKeys f0 <> fieldKeys f1) & UUnbound & newVar binding
        _ <- RowExtend f0 restVar & mkExtend >>= unify r1
        RowExtend f1 restVar & mkExtend
            >>= unify r0
            <&> RowExtend f0

inferRowExtend ::
    forall m val rowTyp key a.
    ( Infer m val
    , Unify m rowTyp
    ) =>
    (Set key -> TypeConstraintsOf rowTyp -> TypeConstraintsOf rowTyp) ->
    (Tree (UVar m) rowTyp -> m (Tree (UVar m) (TypeAST val))) ->
    (Tree (RowExtend key (TypeAST val) rowTyp) (UVar m) -> Tree rowTyp (UVar m)) ->
    Tree (RowExtend key val val) (Ann a) ->
    m
    ( Tree (UVar m) rowTyp
    , Tree (RowExtend key val val) (Ann (TypeOf m val, a))
    )
inferRowExtend forbid rowToTyp extendToRow (RowExtend fields rest) =
    withDict (recursive :: RecursiveDict (Unify m) (TypeAST val)) $
    do
        (fieldsT, fieldsI) <- inferTermMap fields
        restI <- inferNode rest
        restVar <-
            scopeConstraintsForType (Proxy :: Proxy rowTyp)
            >>= newVar binding . UUnbound . forbid (fieldKeys fields)
        _ <- rowToTyp restVar >>= unify (restI ^. nodeType)
        RowExtend fieldsT restVar & extendToRow & newTerm
            <&> (, RowExtend fieldsI restI)