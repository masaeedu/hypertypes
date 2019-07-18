{-# LANGUAGE NoImplicitPrelude, TemplateHaskellQuotes #-}

module AST.Class.Applicative.TH
    ( makeKApplicative, makeKApplicativeAndBase
    ) where

import           AST.Class.Applicative
import           AST.Class.Functor.TH (makeKFunctor)
import           AST.Class.Pointed.TH (makeKPointed)
import           AST.Internal.TH
import           Control.Applicative (liftA2)
import           Control.Lens.Operators
import qualified Data.Map as Map
import           Language.Haskell.TH
import qualified Language.Haskell.TH.Datatype as D

import           Prelude.Compat

makeKApplicativeAndBase :: Name -> DecsQ
makeKApplicativeAndBase x =
    sequenceA
    [ makeKPointed x
    , makeKFunctor x
    , makeKApplicative x
    ] <&> concat

makeKApplicative :: Name -> DecsQ
makeKApplicative typeName = makeTypeInfo typeName >>= makeKApplicativeForType

makeKApplicativeForType :: TypeInfo -> DecsQ
makeKApplicativeForType info =
    do
        cons <-
            case tiCons info of
            [x] -> pure x
            _ -> fail "makeKApplicativeForType only supports types with a single constructor"
        childrenTypes <- getChildrenTypes info
        (childrenCons, childrenSubst) <- getChildrenTypesInfo childrenTypes
        let childrenConsVars = makeConstructorVars "c" childrenCons
        let (directChildVars, embedChildVars) = getChildTypeVars childrenConsVars childrenSubst
        let xVars = makeConstructorVars "x" cons
        let yVars = makeConstructorVars "y" cons
        let bodyForPat (NodeFofX t) =
                case Map.lookup t directChildVars of
                Nothing ->
                    "Failed producing mapC for child of type:\n        " <> show t <>
                    "\n    not in:\n        " <> show directChildVars
                    & fail
                Just x -> VarE 'runLiftK2 `AppE` VarE x & pure
            bodyForPat (XofF t) =
                case Map.lookup t embedChildVars of
                Nothing ->
                    "Failed producing mapC for embedded type:\n        " <> show t <>
                    "\n    not in:\n        " <> show embedChildVars
                    & fail
                Just x -> VarE 'liftC2 `AppE` VarE x & pure
            bodyForPat (Tof _ pat) = bodyForPat pat <&> AppE (VarE 'liftA2)
            bodyForPat Other{} = VarE 'id & pure
        let f (typ, x) (_, y) =
                bodyForPat (matchType (tiVar info) typ)
                <&> \z -> z `AppE` VarE x `AppE` VarE y
        fields <- zipWith f xVars yVars & sequenceA
        instanceD (pure (makeContext info)) (appT (conT ''KApplicative) (pure (tiInstance info)))
            [ InlineP 'liftC2 Inline FunLike AllPhases & PragmaD & pure
            , funD 'liftC2
                [ Clause
                    [ consPat childrenCons childrenConsVars
                    , consPat cons xVars
                    , consPat cons yVars
                    ] (NormalB (foldl AppE (ConE (D.constructorName cons)) fields)) []
                    & pure
                ]
            ]
            <&> (:[])

makeContext :: TypeInfo -> [Pred]
makeContext info =
    tiCons info
    >>= D.constructorFields
    <&> matchType (tiVar info)
    >>= ctxForPat
    where
        ctxForPat (Tof t pat) = [ConT ''Applicative `AppT` t | isPolymorphic t] <> ctxForPat pat
        ctxForPat (XofF t) = [ConT ''KApplicative `AppT` t | isPolymorphic t]
        ctxForPat _ = []
